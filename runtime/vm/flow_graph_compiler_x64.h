// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#ifndef VM_FLOW_GRAPH_COMPILER_X64_H_
#define VM_FLOW_GRAPH_COMPILER_X64_H_

#ifndef VM_FLOW_GRAPH_COMPILER_H_
#error Include flow_graph_compiler.h instead of flow_graph_compiler_x64.h.
#endif

#include "vm/assembler.h"
#include "vm/code_generator.h"
#include "vm/intermediate_language.h"

namespace dart {

class ParsedFunction;

class FlowGraphCompiler : public InstructionVisitor {
 public:
  FlowGraphCompiler(Assembler* assembler,
                    const ParsedFunction& parsed_function,
                    const GrowableArray<BlockEntryInstr*>* blocks)
      : assembler_(assembler),
        parsed_function_(parsed_function),
        blocks_(blocks),
        pc_descriptors_list_(new CodeGenerator::DescriptorList()) { }

  virtual ~FlowGraphCompiler() { }

  void CompileGraph();

 private:
  // Bail out of the flow graph compiler.  Does not return to the caller.
  void Bailout(const char* reason);

  // Each visit function compiles a type of instruction.
#define DECLARE_VISIT(type)                             \
  virtual void Visit##type(type##Instr* instr);
  FOR_EACH_INSTRUCTION(DECLARE_VISIT)
#undef DECLARE_VISIT

  // Emit code to load a Value into register RAX.
  void LoadValue(Value* value);

  // Infrastructure copied from class CodeGenerator.
  void GenerateCallRuntime(intptr_t node_id,
                           intptr_t token_index,
                           const RuntimeEntry& entry);
  void AddCurrentDescriptor(PcDescriptors::Kind kind,
                            intptr_t node_id,
                            intptr_t token_index);

  Assembler* assembler_;
  const ParsedFunction& parsed_function_;
  const GrowableArray<BlockEntryInstr*>* blocks_;

  CodeGenerator::DescriptorList* pc_descriptors_list_;

  DISALLOW_COPY_AND_ASSIGN(FlowGraphCompiler);
};

}  // namespace dart

#endif  // VM_FLOW_GRAPH_COMPILER_X64_H_
