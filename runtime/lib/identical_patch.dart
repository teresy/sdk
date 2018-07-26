// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// part of "core_patch.dart";

@patch
bool identical(Object a, Object b) native "Identical_comparison";

@patch
@pragma("vm.entry-point")
int identityHashCode(Object object) => object._identityHashCode;
