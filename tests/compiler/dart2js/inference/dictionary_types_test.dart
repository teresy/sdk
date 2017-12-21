// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// TODO(johnniwinther): Port this test to use the equivalence framework.

import 'package:async_helper/async_helper.dart';
import 'package:compiler/src/commandline_options.dart';
import 'package:expect/expect.dart';

import '../memory_compiler.dart';

var SOURCES = const {
  'AddAll.dart': """
  var dictionaryA = {'string': "aString", 'int': 42, 'double': 21.5,
                     'list': []};
  var dictionaryB = {'string': "aString", 'int': 42, 'double': 21.5,
                     'list': []};
  var otherDict = {'stringTwo' : "anotherString", 'intTwo' : 84};
  var int = 0;
  var anotherInt = 0;
  var nullOrInt = 0;
  var dynamic = 0;

  main() {
    dictionaryA.addAll(otherDict);
    dictionaryB.addAll({'stringTwo' : "anotherString", 'intTwo' : 84});
    int = dictionaryB['int'];
    anotherInt = otherDict['intTwo'];
    dynamic = dictionaryA['int'];
    nullOrInt = dictionaryB['intTwo'];
  }
""",
  'Union.dart': """
  var dictionaryA = {'string': "aString", 'int': 42, 'double': 21.5,
                     'list': []};
  var dictionaryB = {'string': "aString", 'intTwo': 42, 'list': []};
  var nullOrInt = 0;
  var aString = "";
  var doubleOrNull = 22.2;
  var key = "string";

  main() {
    var union = dictionaryA['foo'] ? dictionaryA : dictionaryB;
    nullOrInt = union['intTwo'];
    aString = union['string'];
    doubleOrNull = union['double'];
  }
""",
  'ValueType.dart': """
  var dictionary = {'string': "aString", 'int': 42, 'double': 21.5, 'list': []};
  var keyD = 'double';
  var keyI = 'int';
  var keyN = 'notFoundInMap';
  var knownDouble = 42.2;
  var intOrNull = dictionary[keyI];
  var justNull = dictionary[keyN];

  main() {
    knownDouble = dictionary[keyD];
    var x = [intOrNull, justNull];
  }
""",
  'Propagation.dart': """
  class A {
    A();
    foo(value) {
      return value['anInt'];
    }
  }

  class B {
    B();
    foo(value) {
      return 0;
    }
  }

  main() {
    var dictionary = {'anInt': 42, 'aString': "theString"};
    var it;
    if ([true, false][0]) {
      it = new A();
    } else {
      it = new B();
    }
    print(it.foo(dictionary) + 2);
  }
""",
  'Bailout.dart': """
  var dict = makeMap([1,2]);
  var notInt = 0;
  var alsoNotInt = 0;

  makeMap(values) {
    return {'moo': values[0], 'boo': values[1]};
  }

  main () {
    dict['goo'] = 42;
    var closure = () => dict;
    notInt = closure()['boo'];
    alsoNotInt = dict['goo'];
    print("\$notInt and \$alsoNotInt.");
  }
"""
};

void main() {
  asyncTest(() async {
    print('--test from ast---------------------------------------------------');
    await runTests(useKernel: false);
    print('--test from kernel------------------------------------------------');
    await runTests(useKernel: true);
  });
}

runTests({bool useKernel}) async {
  await compileAndTest("AddAll.dart", (types, getType, closedWorld) {
    Expect.equals(getType('int'), types.uint31Type);
    Expect.equals(getType('anotherInt'), types.uint31Type);
    Expect.equals(getType('dynamic'), types.dynamicType);
    Expect.equals(getType('nullOrInt'), types.uint31Type.nullable());
  }, useKernel: useKernel);
  await compileAndTest("Union.dart", (types, getType, closedWorld) {
    Expect.equals(getType('nullOrInt'), types.uint31Type.nullable());
    Expect.isTrue(getType('aString').containsOnlyString(closedWorld));
    Expect.equals(getType('doubleOrNull'), types.doubleType.nullable());
  }, useKernel: useKernel);
  await compileAndTest("ValueType.dart", (types, getType, closedWorld) {
    Expect.equals(getType('knownDouble'), types.doubleType);
    Expect.equals(getType('intOrNull'), types.uint31Type.nullable());
    Expect.equals(getType('justNull'), types.nullType);
  }, useKernel: useKernel);
  await compileAndTest("Propagation.dart", (code) {
    Expect.isFalse(code.contains("J.\$add\$ns"));
  }, createCode: true, useKernel: useKernel);
  await compileAndTest("Bailout.dart", (types, getType, closedWorld) {
    Expect.equals(getType('notInt'), types.dynamicType);
    Expect.equals(getType('alsoNotInt'), types.dynamicType);
    Expect.isFalse(getType('dict').isDictionary);
  }, useKernel: useKernel);
}

compileAndTest(source, checker,
    {bool createCode: false, bool useKernel}) async {
  CompilationResult result = await runCompiler(
      entryPoint: Uri.parse('memory:' + source),
      memorySourceFiles: SOURCES,
      beforeRun: (compiler) {
        compiler.stopAfterTypeInference = !createCode;
      },
      options: useKernel ? [Flags.useKernel] : []);
  var compiler = result.compiler;
  var typesInferrer = compiler.globalInference.typesInferrerInternal;
  var closedWorld = typesInferrer.closedWorld;
  var elementEnvironment = closedWorld.elementEnvironment;
  var commonMasks = closedWorld.commonMasks;
  getType(String name) {
    var element = elementEnvironment.lookupLibraryMember(
        elementEnvironment.mainLibrary, name);
    Expect.isNotNull(element, "No class '$name' found.");
    return typesInferrer.getTypeOfMember(element);
  }

  if (!createCode) {
    checker(commonMasks, getType, closedWorld);
  } else {
    var element = elementEnvironment.mainFunction;
    var code = compiler.backend.getGeneratedCode(element);
    checker(code);
  }
}