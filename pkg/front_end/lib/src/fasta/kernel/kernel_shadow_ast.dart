// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// This file declares a "shadow hierarchy" of concrete classes which extend
/// the kernel class hierarchy, adding methods and fields needed by the
/// BodyBuilder.
///
/// Instances of these classes may be created using the factory methods in
/// `ast_factory.dart`.
///
/// Note that these classes represent the Dart language prior to desugaring.
/// When a single Dart construct desugars to a tree containing multiple kernel
/// AST nodes, the shadow class extends the kernel object at the top of the
/// desugared tree.
///
/// This means that in some cases multiple shadow classes may extend the same
/// kernel class, because multiple constructs in Dart may desugar to a tree
/// with the same kind of root node.

import 'dart:core' hide MapEntry;

import 'package:kernel/ast.dart' as kernel show Expression, Initializer;

import 'package:kernel/ast.dart' hide InvalidExpression, InvalidInitializer;

import 'package:kernel/clone.dart' show CloneVisitor;

import 'package:kernel/type_algebra.dart' show Substitution;

import '../../base/instrumentation.dart'
    show
        Instrumentation,
        InstrumentationValueForMember,
        InstrumentationValueForType,
        InstrumentationValueForTypeArgs;

import '../fasta_codes.dart'
    show
        messageSwitchExpressionNotAssignableCause,
        messageVoidExpression,
        noLength,
        templateCantInferTypeDueToCircularity,
        templateCantUseSuperBoundedTypeForInstanceCreation,
        templateForInLoopElementTypeNotAssignable,
        templateForInLoopTypeNotIterable,
        templateIntegerLiteralIsOutOfRange,
        templateSwitchExpressionNotAssignable,
        templateWebLiteralCannotBeRepresentedExactly;

import '../problems.dart' show unhandled, unsupported;

import '../source/source_class_builder.dart' show SourceClassBuilder;

import '../source/source_library_builder.dart' show SourceLibraryBuilder;

import '../type_inference/inference_helper.dart' show InferenceHelper;

import '../type_inference/interface_resolver.dart' show InterfaceResolver;

import '../type_inference/type_inference_engine.dart'
    show
        FieldInitializerInferenceNode,
        IncludesTypeParametersCovariantly,
        InferenceNode,
        TypeInferenceEngine;

import '../type_inference/type_inferrer.dart'
    show
        ExpressionInferenceResult,
        TypeInferrer,
        TypeInferrerDisabled,
        TypeInferrerImpl;

import '../type_inference/type_promotion.dart'
    show TypePromoter, TypePromoterImpl, TypePromotionFact, TypePromotionScope;

import '../type_inference/type_schema.dart' show UnknownType;

import '../type_inference/type_schema_elimination.dart' show greatestClosure;

import '../type_inference/type_schema_environment.dart'
    show TypeSchemaEnvironment, getPositionalParameterType;

import 'body_builder.dart' show combineStatements;

import 'kernel_expression_generator.dart' show makeLet;

/// Indicates whether type inference involving conditional expressions should
/// always use least upper bound.
///
/// A value of `true` matches the behavior of analyzer.  A value of `false`
/// matches the informal specification in
/// https://github.com/dart-lang/sdk/pull/29371.
///
/// TODO(paulberry): once compatibility with analyzer is no longer needed,
/// change this to `false`.
const bool _forceLub = true;

/// Computes the return type of a (possibly factory) constructor.
InterfaceType computeConstructorReturnType(Member constructor) {
  if (constructor is Constructor) {
    return constructor.enclosingClass.thisType;
  } else {
    return constructor.function.returnType;
  }
}

List<DartType> getExplicitTypeArguments(Arguments arguments) {
  if (arguments is ArgumentsJudgment) {
    return arguments._hasExplicitTypeArguments ? arguments.types : null;
  } else {
    // This code path should only be taken in situations where there are no
    // type arguments at all, e.g. calling a user-definable operator.
    assert(arguments.types.isEmpty);
    return null;
  }
}

/// Information associated with a class during type inference.
class ClassInferenceInfo {
  /// The builder associated with this class.
  final SourceClassBuilder builder;

  /// The visitor for determining if a given type makes covariant use of one of
  /// the class's generic parameters, and therefore requires covariant checks.
  IncludesTypeParametersCovariantly needsCheckVisitor;

  /// Getters and methods in the class's API.  May include forwarding nodes.
  final gettersAndMethods = <Member>[];

  /// Setters in the class's API.  May include forwarding nodes.
  final setters = <Member>[];

  ClassInferenceInfo(this.builder);
}

/// Concrete shadow object representing a set of invocation arguments.
class ArgumentsJudgment extends Arguments {
  bool _hasExplicitTypeArguments;

  List<ExpressionJudgment> get positionalJudgments => positional.cast();

  List<NamedExpressionJudgment> get namedJudgments => named.cast();

  ArgumentsJudgment(List<Expression> positional,
      {List<DartType> types, List<NamedExpression> named})
      : _hasExplicitTypeArguments = types != null && types.isNotEmpty,
        super(positional, types: types, named: named);

  static void setNonInferrableArgumentTypes(
      ArgumentsJudgment arguments, List<DartType> types) {
    arguments.types.clear();
    arguments.types.addAll(types);
    arguments._hasExplicitTypeArguments = true;
  }

  static void removeNonInferrableArgumentTypes(ArgumentsJudgment arguments) {
    arguments.types.clear();
    arguments._hasExplicitTypeArguments = false;
  }
}

/// Shadow object for [AsExpression].
class AsJudgment extends AsExpression implements ExpressionJudgment {
  DartType inferredType;

  AsJudgment(Expression operand, DartType type) : super(operand, type);

  ExpressionJudgment get judgment => operand;

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    inferrer.inferExpression(judgment, const UnknownType(), false,
        isVoidAllowed: true);
    inferredType = type;
    return null;
  }
}

/// Concrete shadow object representing an assert initializer in kernel form.
class AssertInitializerJudgment extends AssertInitializer
    implements InitializerJudgment {
  AssertInitializerJudgment(AssertStatement statement) : super(statement);

  AssertStatementJudgment get judgment => statement;

  @override
  void infer(ShadowTypeInferrer inferrer) {
    inferrer.inferStatement(judgment);
  }
}

/// Concrete shadow object representing an assertion statement in kernel form.
class AssertStatementJudgment extends AssertStatement
    implements StatementJudgment {
  AssertStatementJudgment(Expression condition,
      {Expression message, int conditionStartOffset, int conditionEndOffset})
      : super(condition,
            message: message,
            conditionStartOffset: conditionStartOffset,
            conditionEndOffset: conditionEndOffset);

  ExpressionJudgment get conditionJudgment => condition;

  ExpressionJudgment get messageJudgment => message;

  @override
  void infer(ShadowTypeInferrer inferrer) {
    var conditionJudgment = this.conditionJudgment;
    var messageJudgment = this.messageJudgment;
    var expectedType = inferrer.coreTypes.boolClass.rawType;
    inferrer.inferExpression(
        conditionJudgment, expectedType, !inferrer.isTopLevel);
    inferrer.ensureAssignable(expectedType, conditionJudgment.inferredType,
        conditionJudgment, conditionJudgment.fileOffset);
    if (messageJudgment != null) {
      inferrer.inferExpression(messageJudgment, const UnknownType(), false);
    }
  }
}

/// Shadow object for [AwaitExpression].
class AwaitJudgment extends AwaitExpression implements ExpressionJudgment {
  DartType inferredType;

  AwaitJudgment(Expression operand) : super(operand);

  ExpressionJudgment get judgment => operand;

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    if (!inferrer.typeSchemaEnvironment.isEmptyContext(typeContext)) {
      typeContext = inferrer.wrapFutureOrType(typeContext);
    }
    var judgment = this.judgment;
    inferrer.inferExpression(judgment, typeContext, true, isVoidAllowed: true);
    inferredType =
        inferrer.typeSchemaEnvironment.unfutureType(judgment.inferredType);
    return null;
  }
}

/// Concrete shadow object representing a statement block in kernel form.
class BlockJudgment extends Block implements StatementJudgment {
  BlockJudgment(List<Statement> statements) : super(statements);

  List<Statement> get judgments => statements;

  @override
  void infer(ShadowTypeInferrer inferrer) {
    for (var judgment in judgments) {
      inferrer.inferStatement(judgment);
    }
  }
}

/// Concrete shadow object representing a boolean literal in kernel form.
class BoolJudgment extends BoolLiteral implements ExpressionJudgment {
  DartType inferredType;

  BoolJudgment(bool value) : super(value);

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    inferredType = inferrer.coreTypes.boolClass.rawType;
    return null;
  }
}

/// Concrete shadow object representing a break statement in kernel form.
class BreakJudgment extends BreakStatement implements StatementJudgment {
  BreakJudgment(LabeledStatement target) : super(target);

  LabeledStatementJudgment get targetJudgment => target;

  @override
  void infer(ShadowTypeInferrer inferrer) {
    // No inference needs to be done.
  }
}

/// Concrete shadow object representing a continue statement in kernel form.
class ContinueJudgment extends BreakStatement implements StatementJudgment {
  ContinueJudgment(LabeledStatement target) : super(target);

  LabeledStatementJudgment get targetJudgment => target;

  @override
  void infer(ShadowTypeInferrer inferrer) {
    // No inference needs to be done.
  }
}

/// Concrete shadow object representing a cascade expression.
///
/// A cascade expression of the form `a..b()..c()` is represented as the kernel
/// expression:
///
///     let v = a in
///         let _ = v.b() in
///             let _ = v.c() in
///                 v
///
/// In the documentation that follows, `v` is referred to as the "cascade
/// variable"--this is the variable that remembers the value of the expression
/// preceding the first `..` while the cascades are being evaluated.
///
/// After constructing a [CascadeJudgment], the caller should
/// call [finalize] with an expression representing the expression after the
/// `..`.  If a further `..` follows that expression, the caller should call
/// [extend] followed by [finalize] for each subsequent cascade.
class CascadeJudgment extends Let implements ExpressionJudgment {
  DartType inferredType;

  /// Pointer to the last "let" expression in the cascade.
  Let nextCascade;

  /// Creates a [CascadeJudgment] using [variable] as the cascade
  /// variable.  Caller is responsible for ensuring that [variable]'s
  /// initializer is the expression preceding the first `..` of the cascade
  /// expression.
  CascadeJudgment(VariableDeclarationJudgment variable)
      : super(
            variable,
            makeLet(new VariableDeclaration.forValue(new _UnfinishedCascade()),
                new VariableGet(variable))) {
    nextCascade = body;
  }

  ExpressionJudgment get targetJudgment => variable.initializer;

  Iterable<ExpressionJudgment> get cascadeJudgments sync* {
    Let section = body;
    while (true) {
      yield section.variable.initializer;
      if (section.body is! Let) break;
      section = section.body;
    }
  }

  /// Adds a new unfinalized section to the end of the cascade.  Should be
  /// called after the previous cascade section has been finalized.
  void extend() {
    assert(nextCascade.variable.initializer is! _UnfinishedCascade);
    Let newCascade = makeLet(
        new VariableDeclaration.forValue(new _UnfinishedCascade()),
        nextCascade.body);
    nextCascade.body = newCascade;
    newCascade.parent = nextCascade;
    nextCascade = newCascade;
  }

  /// Finalizes the last cascade section with the given [expression].
  void finalize(Expression expression) {
    assert(nextCascade.variable.initializer is _UnfinishedCascade);
    nextCascade.variable.initializer = expression;
    expression.parent = nextCascade.variable;
  }

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    inferredType = inferrer.inferExpression(targetJudgment, typeContext, true);
    if (inferrer.strongMode) {
      variable.type = inferredType;
    }
    for (var judgment in cascadeJudgments) {
      inferrer.inferExpression(judgment, const UnknownType(), false,
          isVoidAllowed: true);
    }
    return null;
  }
}

/// Shadow object representing a class in kernel form.
class ShadowClass extends Class {
  ClassInferenceInfo _inferenceInfo;

  ShadowClass(
      {String name,
      Supertype supertype,
      Supertype mixedInType,
      List<TypeParameter> typeParameters,
      List<Supertype> implementedTypes,
      List<Procedure> procedures,
      List<Field> fields})
      : super(
            name: name,
            supertype: supertype,
            mixedInType: mixedInType,
            typeParameters: typeParameters,
            implementedTypes: implementedTypes,
            procedures: procedures,
            fields: fields);

  /// Resolves all forwarding nodes for this class, propagates covariance
  /// annotations, and creates forwarding stubs as needed.
  void finalizeCovariance(InterfaceResolver interfaceResolver) {
    interfaceResolver.finalizeCovariance(
        this, _inferenceInfo.gettersAndMethods, _inferenceInfo.builder.library);
    interfaceResolver.finalizeCovariance(
        this, _inferenceInfo.setters, _inferenceInfo.builder.library);
    interfaceResolver.recordInstrumentation(this);
  }

  /// Creates API members for this class.
  void setupApiMembers(InterfaceResolver interfaceResolver) {
    interfaceResolver.createApiMembers(this, _inferenceInfo.gettersAndMethods,
        _inferenceInfo.setters, _inferenceInfo.builder.library);
  }

  static void clearClassInferenceInfo(ShadowClass class_) {
    class_._inferenceInfo = null;
  }

  static ClassInferenceInfo getClassInferenceInfo(Class class_) {
    if (class_ is ShadowClass) return class_._inferenceInfo;
    return null;
  }

  /// Initializes the class inference information associated with the given
  /// [class_], starting with the fact that it is associated with the given
  /// [builder].
  static void setBuilder(ShadowClass class_, SourceClassBuilder builder) {
    class_._inferenceInfo = new ClassInferenceInfo(builder);
  }
}

/// Abstract shadow object representing a complex assignment in kernel form.
///
/// Since there are many forms a complex assignment might have been desugared
/// to, this class wraps the desugared assignment rather than extending it.
///
/// TODO(paulberry): once we know exactly what constitutes a "complex
/// assignment", document it here.
abstract class ComplexAssignmentJudgment extends SyntheticExpressionJudgment {
  /// In a compound assignment, the expression that reads the old value, or
  /// `null` if this is not a compound assignment.
  Expression read;

  /// The expression appearing on the RHS of the assignment.
  final ExpressionJudgment rhs;

  /// The expression that performs the write (e.g. `a.[]=(b, a.[](b) + 1)` in
  /// `++a[b]`).
  Expression write;

  /// In a compound assignment without shortcut semantics, the expression that
  /// combines the old and new values, or `null` if this is not a compound
  /// assignment.
  ///
  /// Note that in a compound assignment with shortcut semantics, this is not
  /// used; [nullAwareCombiner] is used instead.
  MethodInvocation combiner;

  /// In a compound assignment with shortcut semantics, the conditional
  /// expression that determines whether the assignment occurs.
  ///
  /// Note that in a compound assignment without shortcut semantics, this is not
  /// used; [combiner] is used instead.
  ConditionalExpression nullAwareCombiner;

  /// Indicates whether the expression arose from a post-increment or
  /// post-decrement.
  bool isPostIncDec = false;

  /// Indicates whether the expression arose from a pre-increment or
  /// pre-decrement.
  bool isPreIncDec = false;

  ComplexAssignmentJudgment(this.rhs) : super(null);

  String toString() {
    var parts = _getToStringParts();
    return '${runtimeType}(${parts.join(', ')})';
  }

  List<String> _getToStringParts() {
    List<String> parts = [];
    if (desugared != null) parts.add('desugared=$desugared');
    if (read != null) parts.add('read=$read');
    if (rhs != null) parts.add('rhs=$rhs');
    if (write != null) parts.add('write=$write');
    if (combiner != null) parts.add('combiner=$combiner');
    if (nullAwareCombiner != null) {
      parts.add('nullAwareCombiner=$nullAwareCombiner');
    }
    if (isPostIncDec) parts.add('isPostIncDec=true');
    if (isPreIncDec) parts.add('isPreIncDec=true');
    return parts;
  }

  DartType _getWriteType(ShadowTypeInferrer inferrer) => unhandled(
      '$runtimeType', 'ShadowComplexAssignment._getWriteType', -1, null);

  _ComplexAssignmentInferenceResult _inferRhs(
      ShadowTypeInferrer inferrer, DartType readType, DartType writeContext) {
    assert(writeContext != null);
    if (readType is VoidType &&
        (combiner != null || nullAwareCombiner != null)) {
      inferrer.helper
          ?.addProblem(messageVoidExpression, read.fileOffset, noLength);
    }
    var writeOffset = write == null ? -1 : write.fileOffset;
    Procedure combinerMember;
    DartType combinedType;
    if (combiner != null) {
      bool isOverloadedArithmeticOperator = false;
      combinerMember =
          inferrer.findMethodInvocationMember(readType, combiner, silent: true);
      if (combinerMember is Procedure) {
        isOverloadedArithmeticOperator = inferrer.typeSchemaEnvironment
            .isOverloadedArithmeticOperatorAndType(combinerMember, readType);
      }
      DartType rhsType;
      var combinerType = inferrer.getCalleeFunctionType(
          inferrer.getCalleeType(combinerMember, readType), false);
      if (isPreIncDec || isPostIncDec) {
        rhsType = inferrer.coreTypes.intClass.rawType;
      } else {
        // It's not necessary to call _storeLetType for [rhs] because the RHS
        // is always passed directly to the combiner; it's never stored in a
        // temporary variable first.
        assert(identical(combiner.arguments.positional.first, rhs));
        // Analyzer uses a null context for the RHS here.
        // TODO(paulberry): improve on this.
        inferrer.inferExpression(rhs, const UnknownType(), true);
        rhsType = rhs.inferredType;
        // Do not use rhs after this point because it may be a Shadow node
        // that has been replaced in the tree with its desugaring.
        var expectedType = getPositionalParameterType(combinerType, 0);
        inferrer.ensureAssignable(expectedType, rhsType,
            combiner.arguments.positional.first, combiner.fileOffset);
      }
      if (isOverloadedArithmeticOperator) {
        combinedType = inferrer.typeSchemaEnvironment
            .getTypeOfOverloadedArithmetic(readType, rhsType);
      } else {
        combinedType = combinerType.returnType;
      }
      var checkKind = inferrer.preCheckInvocationContravariance(read, readType,
          combinerMember, combiner, combiner.arguments, combiner);
      var replacedCombiner = inferrer.handleInvocationContravariance(
          checkKind,
          combiner,
          combiner.arguments,
          combiner,
          combinedType,
          combinerType,
          combiner.fileOffset);
      var replacedCombiner2 = inferrer.ensureAssignable(
          writeContext, combinedType, replacedCombiner, writeOffset);
      if (replacedCombiner2 != null) {
        replacedCombiner = replacedCombiner2;
      }
      _storeLetType(inferrer, replacedCombiner, combinedType);
    } else {
      inferrer.inferExpression(rhs, writeContext ?? const UnknownType(), true,
          isVoidAllowed: true);
      var rhsType = rhs.inferredType;
      var replacedRhs = inferrer.ensureAssignable(
          writeContext, rhsType, rhs, writeOffset,
          isVoidAllowed: writeContext is VoidType);
      _storeLetType(inferrer, replacedRhs ?? rhs, rhsType);
      if (nullAwareCombiner != null) {
        MethodInvocation equalsInvocation = nullAwareCombiner.condition;
        inferrer.findMethodInvocationMember(
            greatestClosure(inferrer.coreTypes, writeContext), equalsInvocation,
            silent: true);
        // Note: the case of readType=null only happens for erroneous code.
        combinedType = readType == null
            ? rhsType
            : inferrer.typeSchemaEnvironment
                .getStandardUpperBound(readType, rhsType);
        if (inferrer.strongMode) {
          nullAwareCombiner.staticType = combinedType;
        }
      } else {
        combinedType = rhsType;
      }
    }
    if (this is IndexAssignmentJudgment) {
      _storeLetType(inferrer, write, const VoidType());
    } else {
      _storeLetType(inferrer, write, combinedType);
    }
    inferredType =
        isPostIncDec ? (readType ?? const DynamicType()) : combinedType;
    return new _ComplexAssignmentInferenceResult(combinerMember);
  }
}

/// Abstract shadow object representing a complex assignment involving a
/// receiver.
abstract class ComplexAssignmentJudgmentWithReceiver
    extends ComplexAssignmentJudgment {
  /// The receiver of the assignment target (e.g. `a` in `a[b] = c`).
  final ExpressionJudgment receiver;

  /// Indicates whether this assignment uses `super`.
  final bool isSuper;

  ComplexAssignmentJudgmentWithReceiver(
      this.receiver, ExpressionJudgment rhs, this.isSuper)
      : super(rhs);

  @override
  List<String> _getToStringParts() {
    var parts = super._getToStringParts();
    if (receiver != null) parts.add('receiver=$receiver');
    if (isSuper) parts.add('isSuper=true');
    return parts;
  }

  DartType _inferReceiver(ShadowTypeInferrer inferrer) {
    if (receiver != null) {
      inferrer.inferExpression(receiver, const UnknownType(), true);
      var receiverType = receiver.inferredType;
      _storeLetType(inferrer, receiver, receiverType);
      return receiverType;
    } else if (isSuper) {
      return inferrer.classHierarchy.getTypeAsInstanceOf(
          inferrer.thisType, inferrer.thisType.classNode.supertype.classNode);
    } else {
      return inferrer.thisType;
    }
  }
}

/// Concrete shadow object representing a conditional expression in kernel form.
/// Shadow object for [ConditionalExpression].
class ConditionalJudgment extends ConditionalExpression
    implements ExpressionJudgment {
  DartType inferredType;

  ExpressionJudgment get conditionJudgment => condition;

  ExpressionJudgment get thenJudgment => then;

  ExpressionJudgment get otherwiseJudgment => otherwise;

  ConditionalJudgment(
      Expression condition, Expression then, Expression otherwise)
      : super(condition, then, otherwise, null);

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    var conditionJudgment = this.conditionJudgment;
    var thenJudgment = this.thenJudgment;
    var otherwiseJudgment = this.otherwiseJudgment;
    var expectedType = inferrer.coreTypes.boolClass.rawType;
    inferrer.inferExpression(
        conditionJudgment, expectedType, !inferrer.isTopLevel);
    inferrer.ensureAssignable(expectedType, conditionJudgment.inferredType,
        condition, condition.fileOffset);
    inferrer.inferExpression(thenJudgment, typeContext, true,
        isVoidAllowed: true);
    bool useLub = _forceLub || typeContext == null;
    inferrer.inferExpression(otherwiseJudgment, typeContext, useLub,
        isVoidAllowed: true);
    inferredType = useLub
        ? inferrer.typeSchemaEnvironment.getStandardUpperBound(
            thenJudgment.inferredType, otherwiseJudgment.inferredType)
        : greatestClosure(inferrer.coreTypes, typeContext);
    if (inferrer.strongMode) {
      staticType = inferredType;
    }
    return null;
  }
}

/// Shadow object for [ConstructorInvocation].
class ConstructorInvocationJudgment extends ConstructorInvocation
    implements ExpressionJudgment {
  DartType inferredType;

  ConstructorInvocationJudgment(Constructor target, ArgumentsJudgment arguments,
      {bool isConst: false})
      : super(target, arguments, isConst: isConst);

  ArgumentsJudgment get argumentJudgments => arguments;

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    var library = inferrer.engine.beingInferred[target];
    if (library != null) {
      // There is a cyclic dependency where inferring the types of the
      // initializing formals of a constructor required us to infer the
      // corresponding field type which required us to know the type of the
      // constructor.
      String name = target.enclosingClass.name;
      if (target.name.name.isNotEmpty) {
        // TODO(ahe): Use `inferrer.helper.constructorNameForDiagnostics`
        // instead. However, `inferrer.helper` may be null.
        name += ".${target.name.name}";
      }
      library.addProblem(
          templateCantInferTypeDueToCircularity.withArguments(name),
          target.fileOffset,
          name.length,
          target.fileUri);
      for (var declaration in target.function.positionalParameters) {
        declaration.type ??= const DynamicType();
      }
      for (var declaration in target.function.namedParameters) {
        declaration.type ??= const DynamicType();
      }
    } else if ((library = inferrer.engine.toBeInferred[target]) != null) {
      inferrer.engine.toBeInferred.remove(target);
      inferrer.engine.beingInferred[target] = library;
      for (var declaration in target.function.positionalParameters) {
        inferrer.engine.inferInitializingFormal(declaration, target);
      }
      for (var declaration in target.function.namedParameters) {
        inferrer.engine.inferInitializingFormal(declaration, target);
      }
      inferrer.engine.beingInferred.remove(target);
    }
    var inferenceResult = inferrer.inferInvocation(
        typeContext,
        fileOffset,
        target.function.functionType,
        computeConstructorReturnType(target),
        argumentJudgments,
        isConst: isConst);
    var inferredType = inferenceResult.type;
    this.inferredType = inferredType;
    if (inferrer.strongMode &&
        !inferrer.isTopLevel &&
        inferrer.typeSchemaEnvironment.isSuperBounded(inferredType)) {
      inferrer.helper.addProblem(
          templateCantUseSuperBoundedTypeForInstanceCreation
              .withArguments(inferredType),
          fileOffset,
          noLength);
    }
    return null;
  }
}

/// Concrete shadow object representing a continue statement from a switch
/// statement, in kernel form.
class ContinueSwitchJudgment extends ContinueSwitchStatement
    implements StatementJudgment {
  ContinueSwitchJudgment(SwitchCase target) : super(target);

  SwitchCaseJudgment get targetJudgment => target;

  @override
  void infer(ShadowTypeInferrer inferrer) {
    // No inference needs to be done.
  }
}

/// Shadow object representing a deferred check in kernel form.
class DeferredCheckJudgment extends Let implements ExpressionJudgment {
  DartType inferredType;

  DeferredCheckJudgment(VariableDeclaration variable, Expression body)
      : super(variable, body);

  ExpressionJudgment get judgment => body;

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    // Since the variable is not used in the body we don't need to type infer
    // it.  We can just type infer the body.
    var judgment = this.judgment;
    inferrer.inferExpression(judgment, typeContext, true, isVoidAllowed: true);
    inferredType = judgment.inferredType;
    return null;
  }
}

/// Concrete shadow object representing a do loop in kernel form.
class DoJudgment extends DoStatement implements StatementJudgment {
  DoJudgment(Statement body, Expression condition) : super(body, condition);

  StatementJudgment get bodyJudgment => body;

  ExpressionJudgment get conditionJudgment => condition;

  @override
  void infer(ShadowTypeInferrer inferrer) {
    var conditionJudgment = this.conditionJudgment;
    inferrer.inferStatement(bodyJudgment);
    var boolType = inferrer.coreTypes.boolClass.rawType;
    inferrer.inferExpression(conditionJudgment, boolType, !inferrer.isTopLevel);
    inferrer.ensureAssignable(boolType, conditionJudgment.inferredType,
        condition, condition.fileOffset);
  }
}

/// Concrete shadow object representing a double literal in kernel form.
class DoubleJudgment extends DoubleLiteral implements ExpressionJudgment {
  DartType inferredType;

  DoubleJudgment(double value) : super(value);

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    inferredType = inferrer.coreTypes.doubleClass.rawType;
    return null;
  }
}

/// Common base class for shadow objects representing expressions in kernel
/// form.
abstract class ExpressionJudgment extends Expression {
  DartType inferredType;

  /// Calls back to [inferrer] to perform type inference for whatever concrete
  /// type of [ExpressionJudgment] this is.
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext);
}

/// Concrete shadow object representing an empty statement in kernel form.
class EmptyStatementJudgment extends EmptyStatement
    implements StatementJudgment {
  EmptyStatementJudgment();

  @override
  void infer(ShadowTypeInferrer inferrer) {
    // No inference needs to be done.
  }
}

/// Concrete shadow object representing an expression statement in kernel form.
class ExpressionStatementJudgment extends ExpressionStatement
    implements StatementJudgment {
  ExpressionStatementJudgment(Expression expression) : super(expression);

  Expression get judgment => expression;

  @override
  void infer(ShadowTypeInferrer inferrer) {
    inferrer.inferExpression(judgment, const UnknownType(), false,
        isVoidAllowed: true);
  }
}

/// Shadow object for [StaticInvocation] when the procedure being invoked is a
/// factory constructor.
class FactoryConstructorInvocationJudgment extends StaticInvocation
    implements ExpressionJudgment {
  DartType inferredType;

  FactoryConstructorInvocationJudgment(
      Procedure target, ArgumentsJudgment arguments,
      {bool isConst: false})
      : super(target, arguments, isConst: isConst);

  ArgumentsJudgment get argumentJudgments => arguments;

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    var inferenceResult = inferrer.inferInvocation(
        typeContext,
        fileOffset,
        target.function.functionType,
        computeConstructorReturnType(target),
        argumentJudgments,
        isConst: isConst);
    inferredType = inferenceResult.type;
    return null;
  }
}

/// Concrete shadow object representing a field in kernel form.
class ShadowField extends Field implements ShadowMember {
  @override
  InferenceNode inferenceNode;

  ShadowTypeInferrer _typeInferrer;

  final bool _isImplicitlyTyped;

  ShadowField(Name name, this._isImplicitlyTyped, {Uri fileUri})
      : super(name, fileUri: fileUri) {}

  @override
  void setInferredType(
      TypeInferenceEngine engine, Uri uri, DartType inferredType) {
    type = inferredType;
  }

  static bool hasTypeInferredFromInitializer(ShadowField field) =>
      field.inferenceNode is FieldInitializerInferenceNode;

  static bool isImplicitlyTyped(ShadowField field) => field._isImplicitlyTyped;

  static void setInferenceNode(ShadowField field, InferenceNode node) {
    assert(field.inferenceNode == null);
    field.inferenceNode = node;
  }
}

/// Concrete shadow object representing a field initializer in kernel form.
class ShadowFieldInitializer extends FieldInitializer
    implements InitializerJudgment {
  ShadowFieldInitializer(Field field, Expression value) : super(field, value);

  @override
  void infer(ShadowTypeInferrer inferrer) {
    var initializerType = inferrer.inferExpression(value, field.type, true);
    inferrer.ensureAssignable(field.type, initializerType, value, fileOffset);
  }
}

/// Concrete shadow object representing a for-in loop in kernel form.
class ForInJudgment extends ForInStatement implements StatementJudgment {
  final bool _declaresVariable;

  final SyntheticExpressionJudgment _syntheticAssignment;

  ForInJudgment(VariableDeclaration variable, Expression iterable,
      Statement body, this._declaresVariable, this._syntheticAssignment,
      {bool isAsync: false})
      : super(variable, iterable, body, isAsync: isAsync);

  VariableDeclarationJudgment get variableJudgment => variable;

  ExpressionJudgment get iterableJudgment => iterable;

  StatementJudgment get bodyJudgment => body;

  @override
  void infer(ShadowTypeInferrer inferrer) {
    var iterableClass = isAsync
        ? inferrer.coreTypes.streamClass
        : inferrer.coreTypes.iterableClass;
    DartType context;
    bool typeNeeded = false;
    bool typeChecksNeeded = !inferrer.isTopLevel;
    VariableDeclarationJudgment variable;
    var syntheticAssignment = _syntheticAssignment;
    DartType syntheticWriteType;
    if (_declaresVariable) {
      variable = this.variableJudgment;
      if (inferrer.strongMode && variable._implicitlyTyped) {
        typeNeeded = true;
        context = const UnknownType();
      } else {
        context = variable.type;
      }
    } else if (syntheticAssignment is ComplexAssignmentJudgment) {
      syntheticWriteType =
          context = syntheticAssignment._getWriteType(inferrer);
    } else {
      context = const UnknownType();
    }
    context = inferrer.wrapType(context, iterableClass);

    var iterableJudgment = this.iterableJudgment;
    inferrer.inferExpression(
        iterableJudgment, context, typeNeeded || typeChecksNeeded);
    var inferredExpressionType =
        inferrer.resolveTypeParameter(iterableJudgment.inferredType);
    inferrer.ensureAssignable(
        inferrer.wrapType(const DynamicType(), iterableClass),
        inferredExpressionType,
        iterable,
        iterable.fileOffset,
        template: templateForInLoopTypeNotIterable);

    DartType inferredType;
    if (typeNeeded || typeChecksNeeded) {
      inferredType = const DynamicType();
      if (inferredExpressionType is InterfaceType) {
        InterfaceType supertype = inferrer.classHierarchy
            .getTypeAsInstanceOf(inferredExpressionType, iterableClass);
        if (supertype != null) {
          inferredType = supertype.typeArguments[0];
        }
      }
      if (typeNeeded) {
        inferrer.instrumentation?.record(inferrer.uri, variable.fileOffset,
            'type', new InstrumentationValueForType(inferredType));
        variable.type = inferredType;
      }
      if (!_declaresVariable) {
        this.variable.type = inferredType;
      }
    }

    inferrer.inferStatement(bodyJudgment);
    if (syntheticAssignment != null) {
      var syntheticStatement = new ExpressionStatement(syntheticAssignment);
      body = combineStatements(syntheticStatement, body)..parent = this;
    }
    if (_declaresVariable) {
      inferrer.inferMetadataKeepingHelper(variable.annotations);
      var tempVar =
          new VariableDeclaration(null, type: inferredType, isFinal: true);
      var variableGet = new VariableGet(tempVar)
        ..fileOffset = this.variable.fileOffset;
      var implicitDowncast = inferrer.ensureAssignable(
          variable.type, inferredType, variableGet, fileOffset,
          template: templateForInLoopElementTypeNotAssignable);
      if (implicitDowncast != null) {
        this.variable = tempVar..parent = this;
        variable.initializer = implicitDowncast..parent = variable;
        body = combineStatements(variable, body)..parent = this;
      }
    } else if (syntheticAssignment is SyntheticExpressionJudgment) {
      if (syntheticAssignment is ComplexAssignmentJudgment) {
        inferrer.ensureAssignable(
            greatestClosure(inferrer.coreTypes, syntheticWriteType),
            this.variable.type,
            syntheticAssignment.rhs,
            syntheticAssignment.rhs.fileOffset,
            template: templateForInLoopElementTypeNotAssignable,
            isVoidAllowed: true);
        if (syntheticAssignment is PropertyAssignmentJudgment) {
          syntheticAssignment._handleWriteContravariance(
              inferrer, inferrer.thisType);
        }
      }
      syntheticAssignment._replaceWithDesugared();
    }
  }
}

/// Concrete shadow object representing a classic for loop in kernel form.
class ForJudgment extends ForStatement implements StatementJudgment {
  final List<ExpressionJudgment> initializers;

  ForJudgment(List<VariableDeclaration> variables, this.initializers,
      ExpressionJudgment condition, List<Expression> updates, Statement body)
      : super(variables ?? [], condition, updates, body);

  List<VariableDeclarationJudgment> get variableJudgments => variables.cast();

  ExpressionJudgment get conditionJudgment => condition;

  List<ExpressionJudgment> get updateJudgments => updates.cast();

  StatementJudgment get bodyJudgment => body;

  @override
  void infer(ShadowTypeInferrer inferrer) {
    var initializers = this.initializers;
    var conditionJudgment = this.conditionJudgment;
    if (initializers != null) {
      for (var initializer in initializers) {
        variables
            .add(new VariableDeclaration.forValue(initializer)..parent = this);
        inferrer.inferExpression(initializer, const UnknownType(), false,
            isVoidAllowed: true);
      }
    } else {
      for (var variable in variableJudgments) {
        inferrer.inferStatement(variable);
      }
    }
    if (conditionJudgment != null) {
      var expectedType = inferrer.coreTypes.boolClass.rawType;
      inferrer.inferExpression(
          conditionJudgment, expectedType, !inferrer.isTopLevel);
      inferrer.ensureAssignable(expectedType, conditionJudgment.inferredType,
          condition, condition.fileOffset);
    }
    for (var update in updateJudgments) {
      inferrer.inferExpression(update, const UnknownType(), false,
          isVoidAllowed: true);
    }
    inferrer.inferStatement(bodyJudgment);
  }
}

/// Concrete shadow object representing a function expression in kernel form.
class FunctionNodeJudgment extends FunctionNode {
  FunctionNodeJudgment(Statement body,
      {List<TypeParameter> typeParameters,
      List<VariableDeclaration> positionalParameters,
      List<VariableDeclaration> namedParameters,
      int requiredParameterCount,
      DartType returnType: const DynamicType(),
      AsyncMarker asyncMarker: AsyncMarker.Sync,
      AsyncMarker dartAsyncMarker})
      : super(body,
            typeParameters: typeParameters,
            positionalParameters: positionalParameters,
            namedParameters: namedParameters,
            requiredParameterCount: requiredParameterCount,
            returnType: returnType,
            asyncMarker: asyncMarker,
            dartAsyncMarker: dartAsyncMarker);

  ExpressionInferenceResult infer(
      ShadowTypeInferrer inferrer,
      DartType typeContext,
      DartType returnContext,
      int returnTypeInstrumentationOffset) {
    return inferrer.inferLocalFunction(
        this, typeContext, returnTypeInstrumentationOffset, returnContext);
  }
}

/// Concrete shadow object representing a local function declaration in kernel
/// form.
class FunctionDeclarationJudgment extends FunctionDeclaration
    implements StatementJudgment {
  bool _hasImplicitReturnType = false;

  FunctionDeclarationJudgment(
      VariableDeclarationJudgment variable, FunctionNodeJudgment function)
      : super(variable, function);

  VariableDeclarationJudgment get variableJudgment => variable;

  FunctionNodeJudgment get functionJudgment => function;

  @override
  void infer(ShadowTypeInferrer inferrer) {
    inferrer.inferMetadataKeepingHelper(variable.annotations);
    DartType returnContext = _hasImplicitReturnType
        ? (inferrer.strongMode ? null : const DynamicType())
        : function.returnType;
    var inferenceResult =
        functionJudgment.infer(inferrer, null, returnContext, fileOffset);
    variable.type = inferenceResult.type;
  }

  static void setHasImplicitReturnType(
      FunctionDeclarationJudgment declaration, bool hasImplicitReturnType) {
    declaration._hasImplicitReturnType = hasImplicitReturnType;
  }
}

/// Concrete shadow object representing a function expression in kernel form.
class FunctionExpressionJudgment extends FunctionExpression
    implements ExpressionJudgment {
  DartType inferredType;

  FunctionExpressionJudgment(FunctionNodeJudgment function) : super(function);

  FunctionNodeJudgment get judgment => function;

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    var judgment = this.judgment;
    var inferenceResult =
        judgment.infer(inferrer, typeContext, null, fileOffset);
    inferredType = inferenceResult.type;
    return null;
  }
}

/// Concrete shadow object representing a super initializer in kernel form.
class InvalidSuperInitializerJudgment extends LocalInitializer
    implements InitializerJudgment {
  final Constructor target;
  final ArgumentsJudgment argumentsJudgment;

  InvalidSuperInitializerJudgment(
      this.target, this.argumentsJudgment, VariableDeclaration variable)
      : super(variable);

  @override
  void infer(ShadowTypeInferrer inferrer) {
    var substitution = Substitution.fromSupertype(inferrer.classHierarchy
        .getClassAsInstanceOf(
            inferrer.thisType.classNode, target.enclosingClass));
    inferrer.inferInvocation(
        null,
        fileOffset,
        substitution
            .substituteType(target.function.functionType.withoutTypeParameters),
        inferrer.thisType,
        argumentsJudgment,
        skipTypeArgumentInference: true);
  }
}

/// Concrete shadow object representing an if-null expression.
///
/// An if-null expression of the form `a ?? b` is represented as the kernel
/// expression:
///
///     let v = a in v == null ? b : v
class IfNullJudgment extends Let implements ExpressionJudgment {
  DartType inferredType;

  IfNullJudgment(VariableDeclaration variable, Expression body)
      : super(variable, body);

  @override
  ConditionalExpression get body => super.body;

  /// Returns the expression to the left of `??`.
  ExpressionJudgment get leftJudgment => variable.initializer;

  /// Returns the expression to the right of `??`.
  ExpressionJudgment get rightJudgment => body.then;

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    var leftJudgment = this.leftJudgment;
    var rightJudgment = this.rightJudgment;
    // To infer `e0 ?? e1` in context K:
    // - Infer e0 in context K to get T0
    inferrer.inferExpression(leftJudgment, typeContext, true);
    var lhsType = leftJudgment.inferredType;
    if (inferrer.strongMode) {
      variable.type = lhsType;
    }
    // - Let J = T0 if K is `?` else K.
    // - Infer e1 in context J to get T1
    bool useLub = _forceLub || typeContext is UnknownType;
    if (typeContext is UnknownType) {
      inferrer.inferExpression(rightJudgment, lhsType, true,
          isVoidAllowed: true);
    } else {
      inferrer.inferExpression(rightJudgment, typeContext, _forceLub,
          isVoidAllowed: true);
    }
    var rhsType = rightJudgment.inferredType;
    // - Let T = greatest closure of K with respect to `?` if K is not `_`, else
    //   UP(t0, t1)
    // - Then the inferred type is T.
    inferredType = useLub
        ? inferrer.typeSchemaEnvironment.getStandardUpperBound(lhsType, rhsType)
        : greatestClosure(inferrer.coreTypes, typeContext);
    if (inferrer.strongMode) {
      body.staticType = inferredType;
    }
    return null;
  }
}

/// Concrete shadow object representing an if statement in kernel form.
class IfJudgment extends IfStatement implements StatementJudgment {
  IfJudgment(Expression condition, Statement then, Statement otherwise)
      : super(condition, then, otherwise);

  ExpressionJudgment get conditionJudgment => condition;

  StatementJudgment get thenJudgment => then;

  StatementJudgment get otherwiseJudgment => otherwise;

  @override
  void infer(ShadowTypeInferrer inferrer) {
    var conditionJudgment = this.conditionJudgment;
    var expectedType = inferrer.coreTypes.boolClass.rawType;
    inferrer.inferExpression(
        conditionJudgment, expectedType, !inferrer.isTopLevel);
    inferrer.ensureAssignable(expectedType, conditionJudgment.inferredType,
        condition, condition.fileOffset);
    inferrer.inferStatement(thenJudgment);
    if (otherwiseJudgment != null) {
      inferrer.inferStatement(otherwiseJudgment);
    }
  }
}

/// Concrete shadow object representing an assignment to a target for which
/// assignment is not allowed.
class IllegalAssignmentJudgment extends ComplexAssignmentJudgment {
  /// The offset at which the invalid assignment should be stored.
  /// If `-1`, then there is no separate location for invalid assignment.
  final int assignmentOffset;

  IllegalAssignmentJudgment(ExpressionJudgment rhs, {this.assignmentOffset: -1})
      : super(rhs) {
    rhs.parent = this;
  }

  @override
  DartType _getWriteType(ShadowTypeInferrer inferrer) {
    return const UnknownType();
  }

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    if (write != null) {
      inferrer.inferExpression(write, const UnknownType(), false);
    }
    inferrer.inferExpression(rhs, const UnknownType(), false);
    _replaceWithDesugared();
    inferredType = const DynamicType();
    return null;
  }
}

/// Concrete shadow object representing an assignment to a target of the form
/// `a[b]`.
class IndexAssignmentJudgment extends ComplexAssignmentJudgmentWithReceiver {
  /// In an assignment to an index expression, the index expression.
  final ExpressionJudgment index;

  IndexAssignmentJudgment(
      ExpressionJudgment receiver, this.index, ExpressionJudgment rhs,
      {bool isSuper: false})
      : super(receiver, rhs, isSuper);

  Arguments _getInvocationArguments(
      ShadowTypeInferrer inferrer, Expression invocation) {
    if (invocation is MethodInvocation) {
      return invocation.arguments;
    } else if (invocation is SuperMethodInvocation) {
      return invocation.arguments;
    } else {
      throw unhandled("${invocation.runtimeType}", "_getInvocationArguments",
          fileOffset, inferrer.uri);
    }
  }

  @override
  List<String> _getToStringParts() {
    var parts = super._getToStringParts();
    if (index != null) parts.add('index=$index');
    return parts;
  }

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    var receiverType = _inferReceiver(inferrer);
    var writeMember = inferrer.findMethodInvocationMember(receiverType, write);
    // To replicate analyzer behavior, we base type inference on the write
    // member.  TODO(paulberry): would it be better to use the read member
    // when doing compound assignment?
    var calleeType = inferrer.getCalleeFunctionType(
        inferrer.getCalleeType(writeMember, receiverType), false);
    DartType expectedIndexTypeForWrite;
    DartType indexContext = const UnknownType();
    DartType writeContext = const UnknownType();
    if (calleeType.positionalParameters.length >= 2) {
      // TODO(paulberry): we ought to get a context for the index expression
      // from the index formal parameter, but analyzer doesn't so for now we
      // replicate its behavior.
      expectedIndexTypeForWrite = calleeType.positionalParameters[0];
      writeContext = calleeType.positionalParameters[1];
    }
    inferrer.inferExpression(index, indexContext, true);
    var indexType = index.inferredType;
    _storeLetType(inferrer, index, indexType);
    if (writeContext is! UnknownType) {
      inferrer.ensureAssignable(
          expectedIndexTypeForWrite,
          indexType,
          _getInvocationArguments(inferrer, write).positional[0],
          write.fileOffset);
    }
    InvocationExpression read = this.read;
    DartType readType;
    if (read != null) {
      var readMember =
          inferrer.findMethodInvocationMember(receiverType, read, silent: true);
      var calleeFunctionType = inferrer.getCalleeFunctionType(
          inferrer.getCalleeType(readMember, receiverType), false);
      inferrer.ensureAssignable(
          getPositionalParameterType(calleeFunctionType, 0),
          indexType,
          _getInvocationArguments(inferrer, read).positional[0],
          read.fileOffset);
      readType = calleeFunctionType.returnType;
      var desugaredInvocation = read is MethodInvocation ? read : null;
      var checkKind = inferrer.preCheckInvocationContravariance(receiver,
          receiverType, readMember, desugaredInvocation, read.arguments, read);
      var replacedRead = inferrer.handleInvocationContravariance(
          checkKind,
          desugaredInvocation,
          read.arguments,
          read,
          readType,
          calleeFunctionType,
          read.fileOffset);
      _storeLetType(inferrer, replacedRead, readType);
    }
    _inferRhs(inferrer, readType, writeContext);
    _replaceWithDesugared();
    return null;
  }
}

/// Common base class for shadow objects representing initializers in kernel
/// form.
abstract class InitializerJudgment implements Initializer {
  /// Performs type inference for whatever concrete type of [InitializerJudgment]
  /// this is.
  void infer(ShadowTypeInferrer inferrer);
}

Expression checkWebIntLiteralsErrorIfUnexact(
    ShadowTypeInferrer inferrer, int value, String literal, int charOffset) {
  if (value >= 0 && value <= (1 << 53)) return null;
  if (inferrer.library == null) return null;
  if (!inferrer.library.loader.target.backendTarget
      .errorOnUnexactWebIntLiterals) return null;
  BigInt asInt = BigInt.from(value).toUnsigned(64);
  BigInt asDouble = BigInt.from(asInt.toDouble());
  if (asInt == asDouble) return null;
  String text = literal ?? value.toString();
  String nearest = text.startsWith('0x') || text.startsWith('0X')
      ? '0x${asDouble.toRadixString(16)}'
      : asDouble.toString();
  int length = literal?.length ?? noLength;
  return inferrer.helper
      .buildProblem(
          templateWebLiteralCannotBeRepresentedExactly.withArguments(
              text, nearest),
          charOffset,
          length)
      .desugared;
}

/// Concrete shadow object representing an integer literal in kernel form.
class IntJudgment extends IntLiteral implements ExpressionJudgment {
  DartType inferredType;
  final String literal;

  IntJudgment(int value, this.literal) : super(value);

  double asDouble({bool negated: false}) {
    if (value == 0 && negated) return -0.0;
    BigInt intValue = BigInt.from(negated ? -value : value);
    double doubleValue = intValue.toDouble();
    return intValue == BigInt.from(doubleValue) ? doubleValue : null;
  }

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    if (inferrer.isDoubleContext(typeContext)) {
      double doubleValue = asDouble();
      if (doubleValue != null) {
        parent.replaceChild(
            this, DoubleLiteral(doubleValue)..fileOffset = fileOffset);
        inferredType = inferrer.coreTypes.doubleClass.rawType;
        return null;
      }
    }
    Expression error =
        checkWebIntLiteralsErrorIfUnexact(inferrer, value, literal, fileOffset);
    if (error != null) {
      parent.replaceChild(this, error);
      inferredType = const BottomType();
      return null;
    }
    inferredType = inferrer.coreTypes.intClass.rawType;
    return null;
  }
}

class ShadowLargeIntLiteral extends IntLiteral implements ExpressionJudgment {
  final String literal;
  final int fileOffset;
  bool isParenthesized = false;

  DartType inferredType;

  ShadowLargeIntLiteral(this.literal, this.fileOffset) : super(0);

  double asDouble({bool negated: false}) {
    BigInt intValue = BigInt.tryParse(negated ? '-${literal}' : literal);
    if (intValue == null) return null;
    double doubleValue = intValue.toDouble();
    return !doubleValue.isNaN &&
            !doubleValue.isInfinite &&
            intValue == BigInt.from(doubleValue)
        ? doubleValue
        : null;
  }

  int asInt64({bool negated: false}) {
    return int.tryParse(negated ? '-${literal}' : literal);
  }

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    if (inferrer.isDoubleContext(typeContext)) {
      double doubleValue = asDouble();
      if (doubleValue != null) {
        parent.replaceChild(
            this, DoubleLiteral(doubleValue)..fileOffset = fileOffset);
        inferredType = inferrer.coreTypes.doubleClass.rawType;
        return null;
      }
    }

    int intValue = asInt64();
    if (intValue == null) {
      Expression replacement = inferrer.helper.buildProblem(
          templateIntegerLiteralIsOutOfRange.withArguments(literal),
          fileOffset,
          literal.length);
      parent.replaceChild(this, replacement);
      inferredType = const BottomType();
      return null;
    }
    Expression error = checkWebIntLiteralsErrorIfUnexact(
        inferrer, intValue, literal, fileOffset);
    if (error != null) {
      parent.replaceChild(this, error);
      inferredType = const BottomType();
      return null;
    }
    parent.replaceChild(this, IntLiteral(intValue)..fileOffset = fileOffset);
    inferredType = inferrer.coreTypes.intClass.rawType;
    return null;
  }
}

/// Concrete shadow object representing an invalid initializer in kernel form.
class ShadowInvalidInitializer extends LocalInitializer
    implements InitializerJudgment {
  ShadowInvalidInitializer(VariableDeclaration variable) : super(variable);

  @override
  void infer(ShadowTypeInferrer inferrer) {
    inferrer.inferExpression(variable.initializer, const UnknownType(), false);
  }
}

/// Concrete shadow object representing an invalid initializer in kernel form.
class ShadowInvalidFieldInitializer extends LocalInitializer
    implements InitializerJudgment {
  final Field field;
  final Expression value;

  ShadowInvalidFieldInitializer(
      this.field, this.value, VariableDeclaration variable)
      : super(variable) {
    value?.parent = this;
  }

  ExpressionJudgment get judgment => value;

  @override
  void infer(ShadowTypeInferrer inferrer) {
    inferrer.inferExpression(value, field.type, false);
  }
}

/// Concrete shadow object representing a non-inverted "is" test in kernel form.
class IsJudgment extends IsExpression implements ExpressionJudgment {
  DartType inferredType;

  ExpressionJudgment get judgment => operand;

  IsJudgment(Expression operand, DartType type) : super(operand, type);

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    inferrer.inferExpression(judgment, const UnknownType(), false);
    inferredType = inferrer.coreTypes.boolClass.rawType;
    return null;
  }
}

/// Concrete shadow object representing an inverted "is" test in kernel form.
class IsNotJudgment extends Not implements ExpressionJudgment {
  DartType inferredType;

  @override
  IsExpression get operand => super.operand;

  ExpressionJudgment get judgment => operand.operand;

  IsNotJudgment(Expression operand, DartType type, int charOffset)
      : super(new IsExpression(operand, type)..fileOffset = charOffset);

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    inferrer.inferExpression(judgment, const UnknownType(), false);
    inferredType = inferrer.coreTypes.boolClass.rawType;
    return null;
  }
}

/// Concrete shadow object representing a labeled statement in kernel form.
class LabeledStatementJudgment extends LabeledStatement
    implements StatementJudgment {
  LabeledStatementJudgment(Statement body) : super(body);

  StatementJudgment get judgment => body;

  @override
  void infer(ShadowTypeInferrer inferrer) {
    inferrer.inferStatement(judgment);
  }
}

/// Type inference derivation for [LiteralList].
class ListLiteralJudgment extends ListLiteral implements ExpressionJudgment {
  DartType inferredType;

  List<Expression> get judgments => expressions;

  final DartType _declaredTypeArgument;

  ListLiteralJudgment(List<Expression> expressions,
      {DartType typeArgument, bool isConst: false})
      : _declaredTypeArgument = typeArgument,
        super(expressions,
            typeArgument: typeArgument ?? const DynamicType(),
            isConst: isConst);

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    var listClass = inferrer.coreTypes.listClass;
    var listType = listClass.thisType;
    List<DartType> inferredTypes;
    DartType inferredTypeArgument;
    List<DartType> formalTypes;
    List<DartType> actualTypes;
    bool inferenceNeeded = _declaredTypeArgument == null && inferrer.strongMode;
    bool typeChecksNeeded = !inferrer.isTopLevel;
    if (inferenceNeeded || typeChecksNeeded) {
      formalTypes = [];
      actualTypes = [];
    }
    if (inferenceNeeded) {
      inferredTypes = [const UnknownType()];
      inferrer.typeSchemaEnvironment.inferGenericFunctionOrType(listType,
          listClass.typeParameters, null, null, typeContext, inferredTypes,
          isConst: isConst);
      inferredTypeArgument = inferredTypes[0];
    } else {
      inferredTypeArgument = _declaredTypeArgument ?? const DynamicType();
    }
    if (inferenceNeeded || typeChecksNeeded) {
      for (int i = 0; i < judgments.length; ++i) {
        ExpressionJudgment judgment = judgments[i];
        inferrer.inferExpression(
            judgment, inferredTypeArgument, inferenceNeeded || typeChecksNeeded,
            isVoidAllowed: true);
        if (inferenceNeeded) {
          formalTypes.add(listType.typeArguments[0]);
        }
        actualTypes.add(judgment.inferredType);
      }
    }
    if (inferenceNeeded) {
      inferrer.typeSchemaEnvironment.inferGenericFunctionOrType(
          listType,
          listClass.typeParameters,
          formalTypes,
          actualTypes,
          typeContext,
          inferredTypes);
      inferredTypeArgument = inferredTypes[0];
      inferrer.instrumentation?.record(inferrer.uri, fileOffset, 'typeArgs',
          new InstrumentationValueForTypeArgs([inferredTypeArgument]));
      typeArgument = inferredTypeArgument;
    }
    if (typeChecksNeeded) {
      for (int i = 0; i < judgments.length; i++) {
        inferrer.ensureAssignable(
            typeArgument, actualTypes[i], judgments[i], judgments[i].fileOffset,
            isVoidAllowed: typeArgument is VoidType);
      }
    }
    inferredType = new InterfaceType(listClass, [inferredTypeArgument]);
    return null;
  }
}

/// Shadow object for [LogicalExpression].
class LogicalJudgment extends LogicalExpression implements ExpressionJudgment {
  DartType inferredType;

  LogicalJudgment(Expression left, String operator, Expression right)
      : super(left, operator, right);

  ExpressionJudgment get leftJudgment => left;

  ExpressionJudgment get rightJudgment => right;

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    var boolType = inferrer.coreTypes.boolClass.rawType;
    var leftJudgment = this.leftJudgment;
    var rightJudgment = this.rightJudgment;
    inferrer.inferExpression(leftJudgment, boolType, !inferrer.isTopLevel);
    inferrer.inferExpression(rightJudgment, boolType, !inferrer.isTopLevel);
    inferrer.ensureAssignable(
        boolType, leftJudgment.inferredType, left, left.fileOffset);
    inferrer.ensureAssignable(
        boolType, rightJudgment.inferredType, right, right.fileOffset);
    inferredType = boolType;
    return null;
  }
}

/// Type inference derivation for [MapEntry].
///
/// This derivation is needed for uniformity.
class MapEntryJudgment extends MapEntry {
  DartType inferredKeyType;
  DartType inferredValueType;

  ExpressionJudgment get keyJudgment => key;

  ExpressionJudgment get valueJudgment => value;

  MapEntryJudgment(Expression key, Expression value) : super(key, value);

  MapEntry infer(ShadowTypeInferrer inferrer, DartType keyTypeContext,
      DartType valueTypeContext) {
    ExpressionJudgment keyJudgment = this.keyJudgment;
    inferrer.inferExpression(keyJudgment, keyTypeContext, true,
        isVoidAllowed: true);
    inferredKeyType = keyJudgment.inferredType;

    ExpressionJudgment valueJudgment = this.valueJudgment;
    inferrer.inferExpression(valueJudgment, valueTypeContext, true,
        isVoidAllowed: true);
    inferredValueType = valueJudgment.inferredType;

    return null;
  }
}

/// Type inference derivation for [MapLiteral].
class MapLiteralJudgment extends MapLiteral implements ExpressionJudgment {
  DartType inferredType;

  List<MapEntry> get judgments => entries;

  final DartType _declaredKeyType;
  final DartType _declaredValueType;

  MapLiteralJudgment(List<MapEntry> judgments,
      {DartType keyType, DartType valueType, bool isConst: false})
      : _declaredKeyType = keyType,
        _declaredValueType = valueType,
        super(judgments,
            keyType: keyType ?? const DynamicType(),
            valueType: valueType ?? const DynamicType(),
            isConst: isConst);

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    var mapClass = inferrer.coreTypes.mapClass;
    var mapType = mapClass.thisType;
    List<DartType> inferredTypes;
    DartType inferredKeyType;
    DartType inferredValueType;
    List<DartType> formalTypes;
    List<DartType> actualTypes;
    assert((_declaredKeyType == null) == (_declaredValueType == null));
    bool inferenceNeeded = _declaredKeyType == null && inferrer.strongMode;
    bool typeChecksNeeded = !inferrer.isTopLevel;
    if (inferenceNeeded || typeChecksNeeded) {
      formalTypes = [];
      actualTypes = [];
    }
    if (inferenceNeeded) {
      inferredTypes = [const UnknownType(), const UnknownType()];
      inferrer.typeSchemaEnvironment.inferGenericFunctionOrType(mapType,
          mapClass.typeParameters, null, null, typeContext, inferredTypes,
          isConst: isConst);
      inferredKeyType = inferredTypes[0];
      inferredValueType = inferredTypes[1];
    } else {
      inferredKeyType = _declaredKeyType ?? const DynamicType();
      inferredValueType = _declaredValueType ?? const DynamicType();
    }
    List<ExpressionJudgment> cachedKeyJudgments =
        judgments.map((j) => (j as MapEntryJudgment).keyJudgment).toList();
    List<ExpressionJudgment> cachedValueJudgments =
        judgments.map((j) => (j as MapEntryJudgment).valueJudgment).toList();
    if (inferenceNeeded || typeChecksNeeded) {
      for (MapEntryJudgment judgment in judgments) {
        judgment.infer(inferrer, inferredKeyType, inferredValueType);
        if (inferenceNeeded) {
          formalTypes.addAll(mapType.typeArguments);
        }
        actualTypes.add(judgment.inferredKeyType);
        actualTypes.add(judgment.inferredValueType);
      }
    }
    if (inferenceNeeded) {
      inferrer.typeSchemaEnvironment.inferGenericFunctionOrType(
          mapType,
          mapClass.typeParameters,
          formalTypes,
          actualTypes,
          typeContext,
          inferredTypes);
      inferredKeyType = inferredTypes[0];
      inferredValueType = inferredTypes[1];
      inferrer.instrumentation?.record(
          inferrer.uri,
          fileOffset,
          'typeArgs',
          new InstrumentationValueForTypeArgs(
              [inferredKeyType, inferredValueType]));
      keyType = inferredKeyType;
      valueType = inferredValueType;
    }
    if (typeChecksNeeded) {
      for (int i = 0; i < judgments.length; ++i) {
        ExpressionJudgment keyJudgment = cachedKeyJudgments[i];
        inferrer.ensureAssignable(
            keyType, actualTypes[2 * i], keyJudgment, keyJudgment.fileOffset,
            isVoidAllowed: keyType is VoidType);

        ExpressionJudgment valueJudgment = cachedValueJudgments[i];
        inferrer.ensureAssignable(valueType, actualTypes[2 * i + 1],
            valueJudgment, valueJudgment.fileOffset,
            isVoidAllowed: valueType is VoidType);
      }
    }
    inferredType =
        new InterfaceType(mapClass, [inferredKeyType, inferredValueType]);
    return null;
  }
}

/// Abstract shadow object representing a field or procedure in kernel form.
abstract class ShadowMember implements Member {
  Uri get fileUri;

  InferenceNode get inferenceNode;

  void set inferenceNode(InferenceNode value);

  void setInferredType(
      TypeInferenceEngine engine, Uri uri, DartType inferredType);

  static void resolveInferenceNode(Member member) {
    if (member is ShadowMember) {
      if (member.inferenceNode != null) {
        member.inferenceNode.resolve();
        member.inferenceNode = null;
      }
    }
  }
}

/// Shadow object for [MethodInvocation].
class MethodInvocationJudgment extends MethodInvocation
    implements ExpressionJudgment {
  final kernel.Expression desugaredError;
  DartType inferredType;

  /// Indicates whether this method invocation is a call to a `call` method
  /// resulting from the invocation of a function expression.
  final bool _isImplicitCall;

  MethodInvocationJudgment(
      Expression receiver, Name name, ArgumentsJudgment arguments,
      {this.desugaredError, bool isImplicitCall: false, Member interfaceTarget})
      : _isImplicitCall = isImplicitCall,
        super(receiver, name, arguments, interfaceTarget);

  ArgumentsJudgment get argumentJudgments => arguments;

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    if (name.name == 'unary-' &&
        arguments.types.isEmpty &&
        arguments.positional.isEmpty &&
        arguments.named.isEmpty) {
      // Replace integer literals in a double context with the corresponding
      // double literal if it's exact.  For double literals, the negation is
      // folded away.  In any non-double context, or if there is no exact
      // double value, then the corresponding integer literal is left.  The
      // negation is not folded away so that platforms with web literals can
      // distinguish between (non-negated) 0x8000000000000000 represented as
      // integer literal -9223372036854775808 which should be a positive number,
      // and negated 9223372036854775808 represented as
      // -9223372036854775808.unary-() which should be a negative number.
      if (receiver is IntJudgment) {
        IntJudgment receiver = this.receiver;
        if (inferrer.isDoubleContext(typeContext)) {
          double doubleValue = receiver.asDouble(negated: true);
          if (doubleValue != null) {
            parent.replaceChild(
                this, DoubleLiteral(doubleValue)..fileOffset = fileOffset);
            inferredType = inferrer.coreTypes.doubleClass.rawType;
            return null;
          }
        }
        Expression error = checkWebIntLiteralsErrorIfUnexact(
            inferrer, receiver.value, receiver.literal, receiver.fileOffset);
        if (error != null) {
          parent.replaceChild(this, error);
          inferredType = const BottomType();
          return null;
        }
      } else if (receiver is ShadowLargeIntLiteral) {
        ShadowLargeIntLiteral receiver = this.receiver;
        if (!receiver.isParenthesized) {
          if (inferrer.isDoubleContext(typeContext)) {
            double doubleValue = receiver.asDouble(negated: true);
            if (doubleValue != null) {
              parent.replaceChild(
                  this, DoubleLiteral(doubleValue)..fileOffset = fileOffset);
              inferredType = inferrer.coreTypes.doubleClass.rawType;
              return null;
            }
          }
          int intValue = receiver.asInt64(negated: true);
          if (intValue == null) {
            Expression error = inferrer.helper.buildProblem(
                templateIntegerLiteralIsOutOfRange
                    .withArguments(receiver.literal),
                receiver.fileOffset,
                receiver.literal.length);
            parent.replaceChild(this, error);
            inferredType = const BottomType();
            return null;
          }
          if (intValue != null) {
            Expression error = checkWebIntLiteralsErrorIfUnexact(
                inferrer, intValue, receiver.literal, receiver.fileOffset);
            if (error != null) {
              parent.replaceChild(this, error);
              inferredType = const BottomType();
              return null;
            }
            this.receiver = IntLiteral(-intValue)
              ..fileOffset = this.receiver.fileOffset
              ..parent = this;
          }
        }
      }
    }
    var inferenceResult = inferrer.inferMethodInvocation(
        this, receiver, fileOffset, _isImplicitCall, typeContext,
        desugaredInvocation: this);
    inferredType = inferenceResult.type;
    if (desugaredError != null) {
      parent.replaceChild(this, desugaredError);
      parent = null;
    }
    return null;
  }
}

/// Concrete shadow object representing a named function expression.
///
/// Named function expressions are not legal in Dart, but they are accepted by
/// the parser and BodyBuilder for error recovery purposes.
///
/// A named function expression of the form `f() { ... }` is represented as the
/// kernel expression:
///
///     let f = () { ... } in f
class NamedFunctionExpressionJudgment extends Let
    implements ExpressionJudgment {
  DartType inferredType;

  NamedFunctionExpressionJudgment(VariableDeclarationJudgment variable)
      : super(variable, new VariableGet(variable));

  VariableDeclarationJudgment get variableJudgment => variable;

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    ExpressionJudgment initializer = variableJudgment.initializer;
    inferrer.inferExpression(initializer, typeContext, true);
    inferredType = initializer.inferredType;
    if (inferrer.strongMode) variable.type = inferredType;
    return null;
  }
}

/// Shadow object for [Not].
class NotJudgment extends Not implements ExpressionJudgment {
  final bool isSynthetic;

  DartType inferredType;

  NotJudgment(this.isSynthetic, ExpressionJudgment operand) : super(operand);

  ExpressionJudgment get judgment => operand;

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    var judgment = this.judgment;
    // First infer the receiver so we can look up the method that was invoked.
    var boolType = inferrer.coreTypes.boolClass.rawType;
    inferrer.inferExpression(judgment, boolType, !inferrer.isTopLevel);
    inferrer.ensureAssignable(
        boolType, judgment.inferredType, operand, fileOffset);
    inferredType = boolType;
    return null;
  }
}

/// Concrete shadow object representing a null-aware method invocation.
///
/// A null-aware method invocation of the form `a?.b(...)` is represented as the
/// expression:
///
///     let v = a in v == null ? null : v.b(...)
class NullAwareMethodInvocationJudgment extends Let
    implements ExpressionJudgment {
  final kernel.Expression desugaredError;
  DartType inferredType;

  NullAwareMethodInvocationJudgment(
      VariableDeclaration variable, Expression body,
      {this.desugaredError})
      : super(variable, body);

  @override
  ConditionalExpression get body => super.body;

  MethodInvocation get _desugaredInvocation => body.otherwise;

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    var inferenceResult = inferrer.inferMethodInvocation(
        this, variable.initializer, fileOffset, false, typeContext,
        receiverVariable: variable, desugaredInvocation: _desugaredInvocation);
    inferredType = inferenceResult.type;
    if (inferrer.strongMode) {
      body.staticType = inferredType;
    }
    return null;
  }
}

/// Concrete shadow object representing a null-aware read from a property.
///
/// A null-aware property get of the form `a?.b` is represented as the kernel
/// expression:
///
///     let v = a in v == null ? null : v.b
class NullAwarePropertyGetJudgment extends Let implements ExpressionJudgment {
  DartType inferredType;

  NullAwarePropertyGetJudgment(
      VariableDeclaration variable, ConditionalExpression body)
      : super(variable, body);

  @override
  ConditionalExpression get body => super.body;

  PropertyGet get _desugaredGet => body.otherwise;

  ExpressionJudgment get receiverJudgment => variable.initializer;

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    inferrer.inferPropertyGet(
        this, receiverJudgment, fileOffset, false, typeContext,
        receiverVariable: variable, desugaredGet: _desugaredGet);
    if (inferrer.strongMode) {
      body.staticType = inferredType;
    }
    return null;
  }
}

/// Concrete shadow object representing a null literal in kernel form.
class NullJudgment extends NullLiteral implements ExpressionJudgment {
  DartType inferredType;

  NullJudgment();

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    inferredType = inferrer.coreTypes.nullClass.rawType;
    return null;
  }
}

/// Concrete shadow object representing a procedure in kernel form.
class ShadowProcedure extends Procedure implements ShadowMember {
  @override
  InferenceNode inferenceNode;

  final bool _hasImplicitReturnType;

  ShadowProcedure(Name name, ProcedureKind kind, FunctionNode function,
      this._hasImplicitReturnType,
      {Uri fileUri, bool isAbstract: false})
      : super(name, kind, function, fileUri: fileUri, isAbstract: isAbstract);

  @override
  void setInferredType(
      TypeInferenceEngine engine, Uri uri, DartType inferredType) {
    if (isSetter) {
      if (function.positionalParameters.length > 0) {
        function.positionalParameters[0].type = inferredType;
      }
    } else if (isGetter) {
      function.returnType = inferredType;
    } else {
      unhandled("setInferredType", "not accessor", fileOffset, uri);
    }
  }

  static bool hasImplicitReturnType(ShadowProcedure procedure) {
    return procedure._hasImplicitReturnType;
  }
}

/// Concrete shadow object representing an assignment to a property.
class PropertyAssignmentJudgment extends ComplexAssignmentJudgmentWithReceiver {
  /// If this assignment uses null-aware access (`?.`), the conditional
  /// expression that guards the access; otherwise `null`.
  ConditionalExpression nullAwareGuard;

  PropertyAssignmentJudgment(
      ExpressionJudgment receiver, ExpressionJudgment rhs,
      {bool isSuper: false})
      : super(receiver, rhs, isSuper);

  @override
  List<String> _getToStringParts() {
    var parts = super._getToStringParts();
    if (nullAwareGuard != null) parts.add('nullAwareGuard=$nullAwareGuard');
    return parts;
  }

  @override
  DartType _getWriteType(ShadowTypeInferrer inferrer) {
    assert(receiver == null);
    var receiverType = inferrer.thisType;
    var writeMember = inferrer.findPropertySetMember(receiverType, write);
    return inferrer.getSetterType(writeMember, receiverType);
  }

  Object _handleWriteContravariance(
      ShadowTypeInferrer inferrer, DartType receiverType) {
    return inferrer.findPropertySetMember(receiverType, write);
  }

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    var receiverType = _inferReceiver(inferrer);

    DartType readType;
    if (read != null) {
      var readMember =
          inferrer.findPropertyGetMember(receiverType, read, silent: true);
      readType = inferrer.getCalleeType(readMember, receiverType);
      inferrer.handlePropertyGetContravariance(receiver, readMember,
          read is PropertyGet ? read : null, read, readType, read.fileOffset);
      _storeLetType(inferrer, read, readType);
    }
    Member writeMember;
    if (write != null) {
      writeMember = _handleWriteContravariance(inferrer, receiverType);
    }
    // To replicate analyzer behavior, we base type inference on the write
    // member.  TODO(paulberry): would it be better to use the read member when
    // doing compound assignment?
    var writeContext = inferrer.getSetterType(writeMember, receiverType);
    _inferRhs(inferrer, readType, writeContext);
    if (inferrer.strongMode) nullAwareGuard?.staticType = inferredType;
    _replaceWithDesugared();
    return null;
  }
}

/// Shadow object for [PropertyGet].
class PropertyGetJudgment extends PropertyGet implements ExpressionJudgment {
  DartType inferredType;

  final bool forSyntheticToken;

  PropertyGetJudgment(Expression receiver, Name name,
      {Member interfaceTarget, this.forSyntheticToken = false})
      : super(receiver, name, interfaceTarget);

  PropertyGetJudgment.byReference(
      Expression receiver, Name name, Reference interfaceTargetReference)
      : forSyntheticToken = false,
        super.byReference(receiver, name, interfaceTargetReference);

  ExpressionJudgment get receiverJudgment => receiver;

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    inferrer.inferPropertyGet(
        this, receiverJudgment, fileOffset, forSyntheticToken, typeContext,
        desugaredGet: this);
    return null;
  }
}

/// Concrete shadow object representing a redirecting initializer in kernel
/// form.
class RedirectingInitializerJudgment extends RedirectingInitializer
    implements InitializerJudgment {
  RedirectingInitializerJudgment(
      Constructor target, ArgumentsJudgment arguments)
      : super(target, arguments);

  ArgumentsJudgment get argumentJudgments => arguments;

  @override
  infer(ShadowTypeInferrer inferrer) {
    List<TypeParameter> classTypeParameters =
        target.enclosingClass.typeParameters;
    List<DartType> typeArguments =
        new List<DartType>(classTypeParameters.length);
    for (int i = 0; i < typeArguments.length; i++) {
      typeArguments[i] = new TypeParameterType(classTypeParameters[i]);
    }
    ArgumentsJudgment.setNonInferrableArgumentTypes(arguments, typeArguments);
    inferrer.inferInvocation(null, fileOffset, target.function.functionType,
        target.enclosingClass.thisType, argumentJudgments,
        skipTypeArgumentInference: true);
    ArgumentsJudgment.removeNonInferrableArgumentTypes(arguments);
  }
}

/// Shadow object for [Rethrow].
class RethrowJudgment extends Rethrow implements ExpressionJudgment {
  final kernel.Expression desugaredError;

  DartType inferredType;

  RethrowJudgment(this.desugaredError);

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    inferredType = const BottomType();
    if (desugaredError != null) {
      parent.replaceChild(this, desugaredError);
      parent = null;
    }
    return null;
  }
}

/// Concrete shadow object representing a return statement in kernel form.
class ReturnJudgment extends ReturnStatement implements StatementJudgment {
  final String returnKeywordLexeme;

  ReturnJudgment(this.returnKeywordLexeme, [Expression expression])
      : super(expression);

  ExpressionJudgment get judgment => expression;

  @override
  void infer(ShadowTypeInferrer inferrer) {
    var judgment = this.judgment;
    var closureContext = inferrer.closureContext;
    DartType typeContext = !closureContext.isGenerator
        ? closureContext.returnOrYieldContext
        : const UnknownType();
    DartType inferredType;
    if (expression != null) {
      inferrer.inferExpression(judgment, typeContext, true,
          isVoidAllowed: true);
      inferredType = judgment.inferredType;
    } else {
      inferredType = inferrer.coreTypes.nullClass.rawType;
    }
    closureContext.handleReturn(inferrer, this, inferredType,
        !identical(returnKeywordLexeme, "return"));
  }
}

/// Common base class for shadow objects representing statements in kernel
/// form.
abstract class StatementJudgment extends Statement {
  /// Calls back to [inferrer] to perform type inference for whatever concrete
  /// type of [StatementJudgment] this is.
  void infer(ShadowTypeInferrer inferrer);
}

/// Concrete shadow object representing an assignment to a static variable.
class StaticAssignmentJudgment extends ComplexAssignmentJudgment {
  StaticAssignmentJudgment(ExpressionJudgment rhs) : super(rhs);

  @override
  DartType _getWriteType(ShadowTypeInferrer inferrer) {
    StaticSet write = this.write;
    return write.target.setterType;
  }

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    DartType readType = const DynamicType(); // Only used in error recovery
    var read = this.read;
    if (read is StaticGet) {
      readType = read.target.getterType;
      _storeLetType(inferrer, read, readType);
    }
    Member writeMember;
    DartType writeContext = const UnknownType();
    var write = this.write;
    if (write is StaticSet) {
      writeContext = write.target.setterType;
      writeMember = write.target;
      if (writeMember is ShadowField && writeMember.inferenceNode != null) {
        writeMember.inferenceNode.resolve();
        writeMember.inferenceNode = null;
      }
    }
    _inferRhs(inferrer, readType, writeContext);
    _replaceWithDesugared();
    return null;
  }
}

/// Concrete shadow object representing a read of a static variable in kernel
/// form.
class StaticGetJudgment extends StaticGet implements ExpressionJudgment {
  DartType inferredType;

  StaticGetJudgment(Member target) : super(target);

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    var target = this.target;
    if (target is ShadowField && target.inferenceNode != null) {
      target.inferenceNode.resolve();
      target.inferenceNode = null;
    }
    var type = target.getterType;
    if (target is Procedure && target.kind == ProcedureKind.Method) {
      type = inferrer.instantiateTearOff(type, typeContext, this);
    }
    inferredType = type;
    return null;
  }
}

/// Shadow object for [StaticInvocation].
class StaticInvocationJudgment extends StaticInvocation
    implements ExpressionJudgment {
  final kernel.Expression desugaredError;
  DartType inferredType;

  StaticInvocationJudgment(Procedure target, ArgumentsJudgment arguments,
      {this.desugaredError, bool isConst: false})
      : super(target, arguments, isConst: isConst);

  ArgumentsJudgment get argumentJudgments => arguments;

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    FunctionType calleeType = target != null
        ? target.function.functionType
        : new FunctionType([], const DynamicType());
    var inferenceResult = inferrer.inferInvocation(typeContext, fileOffset,
        calleeType, calleeType.returnType, argumentJudgments);
    inferredType = inferenceResult.type;
    if (desugaredError != null) {
      parent.replaceChild(this, desugaredError);
      parent = null;
    }
    return null;
  }
}

/// Concrete shadow object representing a string concatenation in kernel form.
class StringConcatenationJudgment extends StringConcatenation
    implements ExpressionJudgment {
  DartType inferredType;

  StringConcatenationJudgment(List<Expression> expressions)
      : super(expressions);

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    if (!inferrer.isTopLevel) {
      for (var expression in expressions) {
        inferrer.inferExpression(expression, const UnknownType(), false);
      }
    }
    inferredType = inferrer.coreTypes.stringClass.rawType;
    return null;
  }
}

/// Type inference derivation for [StringLiteral].
class StringLiteralJudgment extends StringLiteral
    implements ExpressionJudgment {
  DartType inferredType;

  StringLiteralJudgment(String value) : super(value);

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    inferredType = inferrer.coreTypes.stringClass.rawType;
    return null;
  }
}

/// Concrete shadow object representing a super initializer in kernel form.
class SuperInitializerJudgment extends SuperInitializer
    implements InitializerJudgment {
  SuperInitializerJudgment(Constructor target, ArgumentsJudgment arguments)
      : super(target, arguments);

  ArgumentsJudgment get argumentJudgments => arguments;

  @override
  void infer(ShadowTypeInferrer inferrer) {
    var substitution = Substitution.fromSupertype(inferrer.classHierarchy
        .getClassAsInstanceOf(
            inferrer.thisType.classNode, target.enclosingClass));
    inferrer.inferInvocation(
        null,
        fileOffset,
        substitution
            .substituteType(target.function.functionType.withoutTypeParameters),
        inferrer.thisType,
        argumentJudgments,
        skipTypeArgumentInference: true);
  }
}

/// Shadow object for [SuperMethodInvocation].
class SuperMethodInvocationJudgment extends SuperMethodInvocation
    implements ExpressionJudgment {
  final kernel.Expression desugaredError;
  DartType inferredType;

  SuperMethodInvocationJudgment(Name name, ArgumentsJudgment arguments,
      {this.desugaredError, Procedure interfaceTarget})
      : super(name, arguments, interfaceTarget);

  ArgumentsJudgment get argumentJudgments => arguments;

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    if (interfaceTarget != null) {
      inferrer.instrumentation?.record(inferrer.uri, fileOffset, 'target',
          new InstrumentationValueForMember(interfaceTarget));
    }
    var inferenceResult = inferrer.inferMethodInvocation(
        this, null, fileOffset, false, typeContext,
        interfaceMember: interfaceTarget,
        methodName: name,
        arguments: arguments);
    inferredType = inferenceResult.type;
    if (desugaredError != null) {
      parent.replaceChild(this, desugaredError);
      parent = null;
    }
    return null;
  }
}

/// Shadow object for [SuperPropertyGet].
class SuperPropertyGetJudgment extends SuperPropertyGet
    implements ExpressionJudgment {
  final kernel.Expression desugaredError;
  DartType inferredType;

  SuperPropertyGetJudgment(Name name,
      {this.desugaredError, Member interfaceTarget})
      : super(name, interfaceTarget);

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    if (interfaceTarget != null) {
      inferrer.instrumentation?.record(inferrer.uri, fileOffset, 'target',
          new InstrumentationValueForMember(interfaceTarget));
    }
    inferrer.inferPropertyGet(this, null, fileOffset, false, typeContext,
        interfaceMember: interfaceTarget, propertyName: name);
    if (desugaredError != null) {
      parent.replaceChild(this, desugaredError);
      parent = null;
    }
    return null;
  }
}

/// Concrete shadow object representing a switch case.
class SwitchCaseJudgment extends SwitchCase {
  SwitchCaseJudgment(
      List<Expression> expressions, List<int> expressionOffsets, Statement body,
      {bool isDefault: false})
      : super(expressions, expressionOffsets, body, isDefault: isDefault);

  SwitchCaseJudgment.defaultCase(Statement body) : super.defaultCase(body);

  SwitchCaseJudgment.empty() : super.empty();

  List<ExpressionJudgment> get expressionJudgments => expressions.cast();

  StatementJudgment get bodyJudgment => body;
}

/// Concrete shadow object representing a switch statement in kernel form.
class SwitchStatementJudgment extends SwitchStatement
    implements StatementJudgment {
  SwitchStatementJudgment(Expression expression, List<SwitchCase> cases)
      : super(expression, cases);

  ExpressionJudgment get expressionJudgment => expression;

  List<SwitchCaseJudgment> get caseJudgments => cases.cast();

  @override
  void infer(ShadowTypeInferrer inferrer) {
    var expressionJudgment = this.expressionJudgment;
    inferrer.inferExpression(expressionJudgment, const UnknownType(), true);
    var expressionType = expressionJudgment.inferredType;

    for (var switchCase in caseJudgments) {
      for (var caseExpression in switchCase.expressionJudgments) {
        DartType caseExpressionType =
            inferrer.inferExpression(caseExpression, expressionType, true);

        // Check whether the expression type is assignable to the case expression type.
        if (!inferrer.isAssignable(expressionType, caseExpressionType)) {
          inferrer.helper.addProblem(
              templateSwitchExpressionNotAssignable.withArguments(
                  expressionType, caseExpressionType),
              caseExpression.fileOffset,
              noLength,
              context: [
                messageSwitchExpressionNotAssignableCause.withLocation(
                    inferrer.uri, expressionJudgment.fileOffset, noLength)
              ]);
        }
      }
      inferrer.inferStatement(switchCase.bodyJudgment);
    }
  }
}

/// Shadow object for [SymbolLiteral].
class SymbolLiteralJudgment extends SymbolLiteral
    implements ExpressionJudgment {
  DartType inferredType;

  SymbolLiteralJudgment(String value) : super(value);

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    inferredType = inferrer.coreTypes.symbolClass.rawType;
    return null;
  }
}

/// Synthetic judgment class representing an attempt to invoke an unresolved
/// constructor, or a constructor that cannot be invoked, or a resolved
/// constructor with wrong number of arguments.
// TODO(ahe): Remove this?
class InvalidConstructorInvocationJudgment extends SyntheticExpressionJudgment {
  final Member constructor;
  final Arguments arguments;

  InvalidConstructorInvocationJudgment(
      kernel.Expression desugared, this.constructor, this.arguments)
      : super(desugared);

  ArgumentsJudgment get argumentJudgments => arguments;

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    FunctionType calleeType;
    DartType returnType;
    if (constructor != null) {
      calleeType = constructor.function.functionType;
      returnType = computeConstructorReturnType(constructor);
    } else {
      calleeType = new FunctionType([], const DynamicType());
      returnType = const DynamicType();
    }
    ExpressionInferenceResult inferenceResult = inferrer.inferInvocation(
        typeContext, fileOffset, calleeType, returnType, argumentJudgments);
    this.inferredType = inferenceResult.type;
    return super.infer(inferrer, typeContext);
  }
}

/// Synthetic judgment class representing an attempt to assign to the
/// [expression] which is not assignable.
class InvalidWriteJudgment extends SyntheticExpressionJudgment {
  final ExpressionJudgment expression;

  InvalidWriteJudgment(kernel.Expression desugared, this.expression)
      : super(desugared);

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    // When a compound assignment, the expression is already wrapping in
    // VariableDeclaration in _makeRead(). Otherwise, temporary associate
    // the expression with this node.
    expression.parent ??= this;

    inferrer.inferExpression(expression, const UnknownType(), false);
    return super.infer(inferrer, typeContext);
  }
}

/// Shadow object for expressions that are introduced by the front end as part
/// of desugaring or the handling of error conditions.
///
/// These expressions are removed by type inference and replaced with their
/// desugared equivalents.
class SyntheticExpressionJudgment extends Let implements ExpressionJudgment {
  DartType inferredType;

  SyntheticExpressionJudgment(Expression desugared)
      : super(new VariableDeclaration('_', initializer: new NullLiteral()),
            desugared);

  /// The desugared kernel representation of this synthetic expression.
  Expression get desugared => body;

  void set desugared(Expression value) {
    this.body = value;
    value.parent = this;
  }

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    _replaceWithDesugared();
    inferredType = const DynamicType();
    return null;
  }

  /// Removes this expression from the expression tree, replacing it with
  /// [desugared].
  void _replaceWithDesugared() {
    parent.replaceChild(this, desugared);
    parent = null;
  }

  /// Updates any [Let] nodes in the desugared expression to account for the
  /// fact that [expression] has the given [type].
  void _storeLetType(
      TypeInferrerImpl inferrer, Expression expression, DartType type) {
    if (!inferrer.strongMode) return;
    Expression desugared = this.desugared;
    while (true) {
      if (desugared is Let) {
        Let desugaredLet = desugared;
        var variable = desugaredLet.variable;
        if (identical(variable.initializer, expression)) {
          variable.type = type;
          return;
        }
        desugared = desugaredLet.body;
      } else if (desugared is ConditionalExpression) {
        // When a null-aware assignment is desugared, often the "then" or "else"
        // branch of the conditional expression often contains "let" nodes that
        // need to be updated.
        ConditionalExpression desugaredConditionalExpression = desugared;
        if (desugaredConditionalExpression.then is Let) {
          desugared = desugaredConditionalExpression.then;
        } else {
          desugared = desugaredConditionalExpression.otherwise;
        }
      } else {
        break;
      }
    }
  }
}

class ThisJudgment extends ThisExpression implements ExpressionJudgment {
  DartType inferredType;

  ThisJudgment();

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    inferredType = inferrer.thisType ?? const DynamicType();
    return null;
  }
}

class ThrowJudgment extends Throw implements ExpressionJudgment {
  final kernel.Expression desugaredError;

  DartType inferredType;

  ExpressionJudgment get judgment => expression;

  ThrowJudgment(Expression expression, {this.desugaredError})
      : super(expression);

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    inferrer.inferExpression(judgment, const UnknownType(), false);
    inferredType = const BottomType();
    if (desugaredError != null) {
      parent.replaceChild(this, desugaredError);
      parent = null;
    }
    return null;
  }
}

/// Synthetic judgment class representing a statement that is not allowed at
/// the location it was found, and should be replaced with an error.
class InvalidStatementJudgment extends ExpressionStatement
    implements StatementJudgment {
  final kernel.Expression desugaredError;
  final StatementJudgment statement;

  InvalidStatementJudgment(this.desugaredError, this.statement)
      : super(new NullLiteral());

  @override
  void infer(ShadowTypeInferrer inferrer) {
    inferrer.inferStatement(statement);

    // If this judgment is a part of a Block, replace it there.
    // Otherwise, the parent would be a FunctionNode, but not yet.
    if (parent is Block) {
      parent.replaceChild(this, new ExpressionStatement(desugaredError));
      parent = null;
    }
  }
}

/// Concrete shadow object representing a catch clause.
class CatchJudgment extends Catch {
  CatchJudgment(VariableDeclaration exception, Statement body,
      {DartType guard: const DynamicType(), VariableDeclaration stackTrace})
      : super(exception, body, guard: guard, stackTrace: stackTrace);

  VariableDeclarationJudgment get exceptionJudgment => exception;

  VariableDeclarationJudgment get stackTraceJudgment => stackTrace;

  StatementJudgment get bodyJudgment => body;

  void infer(ShadowTypeInferrer inferrer) {
    inferrer.inferStatement(bodyJudgment);
  }
}

/// Concrete shadow object representing a try-catch block in kernel form.
class TryCatchJudgment extends TryCatch implements StatementJudgment {
  TryCatchJudgment(Statement body, List<Catch> catches) : super(body, catches);

  StatementJudgment get bodyJudgment => body;

  List<CatchJudgment> get catchJudgments => catches.cast();

  @override
  void infer(ShadowTypeInferrer inferrer) {
    inferrer.inferStatement(bodyJudgment);
    for (var catch_ in catchJudgments) {
      catch_.infer(inferrer);
    }
  }
}

/// Concrete shadow object representing a try-finally block in kernel form.
class TryFinallyJudgment extends TryFinally implements StatementJudgment {
  final List<Catch> catches;

  TryFinallyJudgment(Statement body, this.catches, Statement finalizer)
      : super(body, finalizer);

  List<CatchJudgment> get catchJudgments => catches?.cast();

  StatementJudgment get finalizerJudgment => finalizer;

  @override
  void infer(ShadowTypeInferrer inferrer) {
    inferrer.inferStatement(body);
    if (catchJudgments != null) {
      for (var catch_ in catchJudgments) {
        catch_.infer(inferrer);
      }
      body = new TryCatch(body, catches)..parent = this;
    }
    inferrer.inferStatement(finalizerJudgment);
  }
}

/// Concrete implementation of [TypeInferenceEngine] specialized to work with
/// kernel objects.
class ShadowTypeInferenceEngine extends TypeInferenceEngine {
  ShadowTypeInferenceEngine(Instrumentation instrumentation, bool strongMode)
      : super(instrumentation, strongMode);

  @override
  TypeInferrer createDisabledTypeInferrer() =>
      new TypeInferrerDisabled(typeSchemaEnvironment);

  @override
  ShadowTypeInferrer createLocalTypeInferrer(
      Uri uri, InterfaceType thisType, SourceLibraryBuilder library) {
    return new ShadowTypeInferrer._(this, uri, false, thisType, library);
  }

  @override
  ShadowTypeInferrer createTopLevelTypeInferrer(
      InterfaceType thisType, ShadowField field) {
    return field._typeInferrer =
        new ShadowTypeInferrer._(this, field.fileUri, true, thisType, null);
  }

  @override
  ShadowTypeInferrer getFieldTypeInferrer(ShadowField field) {
    return field._typeInferrer;
  }
}

/// Concrete implementation of [TypeInferrer] specialized to work with kernel
/// objects.
class ShadowTypeInferrer extends TypeInferrerImpl {
  @override
  final typePromoter;

  ShadowTypeInferrer._(ShadowTypeInferenceEngine engine, Uri uri, bool topLevel,
      InterfaceType thisType, SourceLibraryBuilder library)
      : typePromoter = new ShadowTypePromoter(engine.typeSchemaEnvironment),
        super(engine, uri, topLevel, thisType, library);

  @override
  Expression getFieldInitializer(ShadowField field) {
    return field.initializer;
  }

  @override
  DartType inferExpression(
      kernel.Expression expression, DartType typeContext, bool typeNeeded,
      {bool isVoidAllowed: false}) {
    // `null` should never be used as the type context.  An instance of
    // `UnknownType` should be used instead.
    assert(typeContext != null);

    // It isn't safe to do type inference on an expression without a parent,
    // because type inference might cause us to have to replace one expression
    // with another, and we can only replace a node if it has a parent pointer.
    assert(expression.parent != null);

    // For full (non-top level) inference, we need access to the
    // ExpressionGeneratorHelper so that we can perform error recovery.
    assert(isTopLevel || helper != null);

    // When doing top level inference, we skip subexpressions whose type isn't
    // needed so that we don't induce bogus dependencies on fields mentioned in
    // those subexpressions.
    if (!typeNeeded && isTopLevel) return null;

    if (expression is ExpressionJudgment) {
      // Use polymorphic dispatch on [KernelExpression] to perform whatever kind
      // of type inference is correct for this kind of statement.
      // TODO(paulberry): experiment to see if dynamic dispatch would be better,
      // so that the type hierarchy will be simpler (which may speed up "is"
      // checks).
      expression.infer(this, typeContext);
      DartType inferredType = expression.inferredType;
      if (inferredType is VoidType && !isVoidAllowed) {
        if (expression.parent is! ArgumentsJudgment) {
          helper?.addProblem(
              messageVoidExpression, expression.fileOffset, noLength);
        }
      }
      return inferredType;
    } else if (expression is IntLiteral) {
      return coreTypes.intClass.rawType;
    } else if (expression is DoubleLiteral) {
      return coreTypes.doubleClass.rawType;
    } else {
      // Encountered an expression type for which type inference is not yet
      // implemented, so just infer dynamic for now.
      // TODO(paulberry): once the BodyBuilder uses shadow classes for
      // everything, this case should no longer be needed.
      return typeNeeded ? const DynamicType() : null;
    }
  }

  @override
  DartType inferFieldTopLevel(ShadowField field, bool typeNeeded) {
    if (field.initializer == null) return const DynamicType();
    return inferExpression(field.initializer, const UnknownType(), typeNeeded,
        isVoidAllowed: true);
  }

  @override
  void inferInitializer(
      InferenceHelper helper, kernel.Initializer initializer) {
    assert(initializer is InitializerJudgment);
    this.helper = helper;
    // Use polymorphic dispatch on [KernelInitializer] to perform whatever
    // kind of type inference is correct for this kind of initializer.
    // TODO(paulberry): experiment to see if dynamic dispatch would be better,
    // so that the type hierarchy will be simpler (which may speed up "is"
    // checks).
    InitializerJudgment kernelInitializer = initializer;
    kernelInitializer.infer(this);
    this.helper = null;
  }

  @override
  void inferStatement(Statement statement) {
    // For full (non-top level) inference, we need access to the
    // ExpressionGeneratorHelper so that we can perform error recovery.
    if (!isTopLevel) assert(helper != null);

    if (statement is StatementJudgment) {
      // Use polymorphic dispatch on [KernelStatement] to perform whatever kind
      // of type inference is correct for this kind of statement.
      // TODO(paulberry): experiment to see if dynamic dispatch would be better,
      // so that the type hierarchy will be simpler (which may speed up "is"
      // checks).
      return statement.infer(this);
    } else {
      // Encountered a statement type for which type inference is not yet
      // implemented, so just skip it for now.
      // TODO(paulberry): once the BodyBuilder uses shadow classes for
      // everything, this case should no longer be needed.
    }
  }
}

class TypeLiteralJudgment extends TypeLiteral implements ExpressionJudgment {
  DartType inferredType;

  TypeLiteralJudgment(DartType type) : super(type);

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    inferredType = inferrer.coreTypes.typeClass.rawType;
    return null;
  }
}

/// Concrete implementation of [TypePromoter] specialized to work with kernel
/// objects.
class ShadowTypePromoter extends TypePromoterImpl {
  ShadowTypePromoter(TypeSchemaEnvironment typeSchemaEnvironment)
      : super(typeSchemaEnvironment);

  @override
  int getVariableFunctionNestingLevel(VariableDeclaration variable) {
    if (variable is VariableDeclarationJudgment) {
      return variable._functionNestingLevel;
    } else {
      // Hack to deal with the fact that BodyBuilder still creates raw
      // VariableDeclaration objects sometimes.
      // TODO(paulberry): get rid of this once the type parameter is
      // KernelVariableDeclaration.
      return 0;
    }
  }

  @override
  bool isPromotionCandidate(VariableDeclaration variable) {
    assert(variable is VariableDeclarationJudgment);
    VariableDeclarationJudgment kernelVariableDeclaration = variable;
    return !kernelVariableDeclaration._isLocalFunction;
  }

  @override
  bool sameExpressions(Expression a, Expression b) {
    return identical(a, b);
  }

  @override
  void setVariableMutatedAnywhere(VariableDeclaration variable) {
    if (variable is VariableDeclarationJudgment) {
      variable._mutatedAnywhere = true;
    } else {
      // Hack to deal with the fact that BodyBuilder still creates raw
      // VariableDeclaration objects sometimes.
      // TODO(paulberry): get rid of this once the type parameter is
      // KernelVariableDeclaration.
    }
  }

  @override
  void setVariableMutatedInClosure(VariableDeclaration variable) {
    if (variable is VariableDeclarationJudgment) {
      variable._mutatedInClosure = true;
    } else {
      // Hack to deal with the fact that BodyBuilder still creates raw
      // VariableDeclaration objects sometimes.
      // TODO(paulberry): get rid of this once the type parameter is
      // KernelVariableDeclaration.
    }
  }

  @override
  bool wasVariableMutatedAnywhere(VariableDeclaration variable) {
    if (variable is VariableDeclarationJudgment) {
      return variable._mutatedAnywhere;
    } else {
      // Hack to deal with the fact that BodyBuilder still creates raw
      // VariableDeclaration objects sometimes.
      // TODO(paulberry): get rid of this once the type parameter is
      // KernelVariableDeclaration.
      return true;
    }
  }
}

class VariableAssignmentJudgment extends ComplexAssignmentJudgment {
  VariableAssignmentJudgment(ExpressionJudgment rhs) : super(rhs);

  @override
  DartType _getWriteType(ShadowTypeInferrer inferrer) {
    VariableSet write = this.write;
    return write.variable.type;
  }

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    DartType readType;
    var read = this.read;
    if (read is VariableGet) {
      readType = read.promotedType ?? read.variable.type;
    }
    DartType writeContext = const UnknownType();
    var write = this.write;
    if (write is VariableSet) {
      writeContext = write.variable.type;
      if (read != null) {
        _storeLetType(inferrer, read, writeContext);
      }
    }
    _inferRhs(inferrer, readType, writeContext);
    _replaceWithDesugared();
    return null;
  }
}

/// Concrete shadow object representing a variable declaration in kernel form.
class VariableDeclarationJudgment extends VariableDeclaration
    implements StatementJudgment {
  final bool forSyntheticToken;

  final bool _implicitlyTyped;

  // TODO(ahe): Remove this field. We can get rid of it by recording closure
  // mutation in [BodyBuilder].
  final int _functionNestingLevel;

  // TODO(ahe): Remove this field. It's only used locally when compiling a
  // method, and this can thus be tracked in a [Set] (actually, tracking this
  // information in a [List] is probably even faster as the average size will
  // be close to zero).
  bool _mutatedInClosure = false;

  // TODO(ahe): Investigate if this can be removed.
  bool _mutatedAnywhere = false;

  // TODO(ahe): Investigate if this can be removed.
  final bool _isLocalFunction;

  /// The same [annotations] list is used for all [VariableDeclarationJudgment]s
  /// of a variable declaration statement. But we need to perform inference
  /// only once. So, we set this flag to `false` for the second and subsequent
  /// judgments.
  bool infersAnnotations = true;

  VariableDeclarationJudgment(String name, this._functionNestingLevel,
      {this.forSyntheticToken: false,
      Expression initializer,
      DartType type,
      bool isFinal: false,
      bool isConst: false,
      bool isFieldFormal: false,
      bool isCovariant: false,
      bool isLocalFunction: false})
      : _implicitlyTyped = type == null,
        _isLocalFunction = isLocalFunction,
        super(name,
            initializer: initializer,
            type: type ?? const DynamicType(),
            isFinal: isFinal,
            isConst: isConst,
            isFieldFormal: isFieldFormal,
            isCovariant: isCovariant);

  VariableDeclarationJudgment.forEffect(
      Expression initializer, this._functionNestingLevel)
      : forSyntheticToken = false,
        _implicitlyTyped = false,
        _isLocalFunction = false,
        super.forValue(initializer);

  VariableDeclarationJudgment.forValue(
      Expression initializer, this._functionNestingLevel)
      : forSyntheticToken = false,
        _implicitlyTyped = true,
        _isLocalFunction = false,
        super.forValue(initializer);

  List<Expression> get annotationJudgments => annotations;

  ExpressionJudgment get initializerJudgment => initializer;

  @override
  void infer(ShadowTypeInferrer inferrer) {
    if (annotationJudgments.isNotEmpty) {
      if (infersAnnotations) {
        inferrer.inferMetadataKeepingHelper(annotationJudgments);
      }

      // After the inference was done on the annotations, we may clone them for
      // this instance of VariableDeclaration in order to avoid having the same
      // annotation node for two VariableDeclaration nodes in a situation like
      // the following:
      //
      //     class Foo { const Foo(List<String> list); }
      //
      //     @Foo(const [])
      //     var x, y;
      CloneVisitor cloner = new CloneVisitor();
      for (int i = 0; i < annotations.length; ++i) {
        kernel.Expression annotation = annotations[i];
        if (annotation.parent != this) {
          annotations[i] = cloner.clone(annotation);
          annotations[i].parent = this;
        }
      }
    }

    var initializerJudgment = this.initializerJudgment;
    var declaredType = _implicitlyTyped ? const UnknownType() : type;
    DartType inferredType;
    DartType initializerType;
    if (initializerJudgment != null) {
      inferrer.inferExpression(initializerJudgment, declaredType,
          !inferrer.isTopLevel || _implicitlyTyped,
          isVoidAllowed: true);
      initializerType = initializerJudgment.inferredType;
      inferredType = inferrer.inferDeclarationType(initializerType);
    } else {
      inferredType = const DynamicType();
    }
    if (inferrer.strongMode && _implicitlyTyped) {
      inferrer.instrumentation?.record(inferrer.uri, fileOffset, 'type',
          new InstrumentationValueForType(inferredType));
      type = inferredType;
    }
    if (initializer != null) {
      var replacedInitializer = inferrer.ensureAssignable(
          type, initializerType, initializer, fileOffset,
          isVoidAllowed: type is VoidType);
      if (replacedInitializer != null) {
        initializer = replacedInitializer;
      }
    }
  }

  /// Determine whether the given [VariableDeclarationJudgment] had an implicit
  /// type.
  ///
  /// This is static to avoid introducing a method that would be visible to
  /// the kernel.
  static bool isImplicitlyTyped(VariableDeclarationJudgment variable) =>
      variable._implicitlyTyped;

  /// Determines whether the given [VariableDeclarationJudgment] represents a
  /// local function.
  ///
  /// This is static to avoid introducing a method that would be visible to the
  /// kernel.
  static bool isLocalFunction(VariableDeclarationJudgment variable) =>
      variable._isLocalFunction;
}

/// Synthetic judgment class representing an attempt to invoke an unresolved
/// target.
class UnresolvedTargetInvocationJudgment extends SyntheticExpressionJudgment {
  final ArgumentsJudgment argumentsJudgment;

  UnresolvedTargetInvocationJudgment(
      kernel.Expression desugared, this.argumentsJudgment)
      : super(desugared);

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    var result = super.infer(inferrer, typeContext);
    inferrer.inferInvocation(
        typeContext,
        fileOffset,
        TypeInferrerImpl.unknownFunction,
        const DynamicType(),
        argumentsJudgment);
    return result;
  }
}

/// Synthetic judgment class representing an attempt to assign to an unresolved
/// variable.
class UnresolvedVariableAssignmentJudgment extends SyntheticExpressionJudgment {
  final bool isCompound;
  final ExpressionJudgment rhs;

  UnresolvedVariableAssignmentJudgment(
      kernel.Expression desugared, this.isCompound, this.rhs)
      : super(desugared);

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    inferrer.inferExpression(rhs, const UnknownType(), true);
    inferredType = isCompound ? const DynamicType() : rhs.inferredType;
    return super.infer(inferrer, typeContext);
  }
}

/// Concrete shadow object representing a read from a variable in kernel form.
class VariableGetJudgment extends VariableGet implements ExpressionJudgment {
  DartType inferredType;

  final TypePromotionFact _fact;

  final TypePromotionScope _scope;

  VariableGetJudgment(VariableDeclaration variable, this._fact, this._scope)
      : super(variable);

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    VariableDeclarationJudgment variable = this.variable;
    bool mutatedInClosure = variable._mutatedInClosure;
    DartType declaredOrInferredType = variable.type;

    DartType promotedType = inferrer.typePromoter
        .computePromotedType(_fact, _scope, mutatedInClosure);
    if (promotedType != null) {
      inferrer.instrumentation?.record(inferrer.uri, fileOffset, 'promotedType',
          new InstrumentationValueForType(promotedType));
    }
    this.promotedType = promotedType;
    var type = promotedType ?? declaredOrInferredType;
    if (variable._isLocalFunction) {
      type = inferrer.instantiateTearOff(type, typeContext, this);
    }
    inferredType = type;
    return null;
  }
}

/// Concrete shadow object representing a while loop in kernel form.
class WhileJudgment extends WhileStatement implements StatementJudgment {
  WhileJudgment(Expression condition, Statement body) : super(condition, body);

  ExpressionJudgment get conditionJudgment => condition;

  StatementJudgment get bodyJudgment => body;

  @override
  void infer(ShadowTypeInferrer inferrer) {
    var conditionJudgment = this.conditionJudgment;
    var expectedType = inferrer.coreTypes.boolClass.rawType;
    inferrer.inferExpression(
        conditionJudgment, expectedType, !inferrer.isTopLevel);
    inferrer.ensureAssignable(expectedType, conditionJudgment.inferredType,
        condition, condition.fileOffset);
    inferrer.inferStatement(bodyJudgment);
  }
}

/// Concrete shadow object representing a yield statement in kernel form.
class YieldJudgment extends YieldStatement implements StatementJudgment {
  YieldJudgment(bool isYieldStar, Expression expression)
      : super(expression, isYieldStar: isYieldStar);

  ExpressionJudgment get judgment => expression;

  @override
  void infer(ShadowTypeInferrer inferrer) {
    var judgment = this.judgment;
    var closureContext = inferrer.closureContext;
    if (closureContext.isGenerator) {
      var typeContext = closureContext.returnOrYieldContext;
      if (isYieldStar && typeContext != null) {
        typeContext = inferrer.wrapType(
            typeContext,
            closureContext.isAsync
                ? inferrer.coreTypes.streamClass
                : inferrer.coreTypes.iterableClass);
      }
      inferrer.inferExpression(judgment, typeContext, true);
    } else {
      inferrer.inferExpression(judgment, const UnknownType(), true);
    }
    closureContext.handleYield(
        inferrer, isYieldStar, judgment.inferredType, expression, fileOffset);
  }
}

/// Concrete shadow object representing a deferred load library call.
class LoadLibraryJudgment extends LoadLibrary implements ExpressionJudgment {
  final Arguments arguments;

  DartType inferredType;

  LoadLibraryJudgment(LibraryDependency import, this.arguments) : super(import);

  ArgumentsJudgment get argumentJudgments => arguments;

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    inferredType =
        inferrer.typeSchemaEnvironment.futureType(const DynamicType());
    if (arguments != null) {
      var calleeType = new FunctionType([], inferredType);
      inferrer.inferInvocation(typeContext, fileOffset, calleeType,
          calleeType.returnType, argumentJudgments);
    }
    return null;
  }
}

/// Concrete shadow object representing a tear-off of a `loadLibrary` function.
class LoadLibraryTearOffJudgment extends StaticGet
    implements ExpressionJudgment {
  final LibraryDependency import;

  DartType inferredType;

  LoadLibraryTearOffJudgment(this.import, Procedure target) : super(target);

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    inferredType = new FunctionType(
        [], inferrer.typeSchemaEnvironment.futureType(const DynamicType()));
    return null;
  }
}

/// Concrete shadow object representing a deferred library-is-loaded check.
class CheckLibraryIsLoadedJudgment extends CheckLibraryIsLoaded
    implements ExpressionJudgment {
  DartType inferredType;

  CheckLibraryIsLoadedJudgment(LibraryDependency import) : super(import);

  @override
  Expression infer(ShadowTypeInferrer inferrer, DartType typeContext) {
    inferredType = inferrer.typeSchemaEnvironment.objectType;
    return null;
  }
}

/// Concrete shadow object representing a named expression.
class NamedExpressionJudgment extends NamedExpression {
  NamedExpressionJudgment(String nameLexeme, Expression value)
      : super(nameLexeme, value);

  ExpressionJudgment get judgment => value;
}

/// The result of inference for a RHS of an assignment.
class _ComplexAssignmentInferenceResult {
  /// The resolved combiner [Procedure], e.g. `operator+` for `a += 2`, or
  /// `null` if the assignment is not compound.
  final Procedure combiner;

  _ComplexAssignmentInferenceResult(this.combiner);
}

class _UnfinishedCascade extends Expression {
  accept(v) => unsupported("accept", -1, null);

  accept1(v, arg) => unsupported("accept1", -1, null);

  getStaticType(types) => unsupported("getStaticType", -1, null);

  transformChildren(v) => unsupported("transformChildren", -1, null);

  visitChildren(v) => unsupported("visitChildren", -1, null);
}
