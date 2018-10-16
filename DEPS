# Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

# IMPORTANT:
# Before adding or updating dependencies, please review the documentation here:
# https://github.com/dart-lang/sdk/wiki/Adding-and-Updating-Dependencies

allowed_hosts = [
  'boringssl.googlesource.com',
  'chrome-infra-packages.appspot.com',
  'chromium.googlesource.com',
  'dart.googlesource.com',
  'fuchsia.googlesource.com',
]

vars = {
  # The dart_root is the root of our sdk checkout. This is normally
  # simply sdk, but if using special gclient specs it can be different.
  "dart_root": "sdk",

  # We use mirrors of all github repos to guarantee reproducibility and
  # consistency between what users see and what the bots see.
  # We need the mirrors to not have 100+ bots pulling github constantly.
  # We mirror our github repos on Dart's git servers.
  # DO NOT use this var if you don't see a mirror here:
  #   https://dart.googlesource.com/
  "dart_git":
      "https://dart.googlesource.com/",
  # If the repo you want to use is at github.com/dart-lang, but not at
  # dart.googlesource.com, please file an issue
  # on github and add the label 'area-infrastructure'.
  # When the repo is mirrored, you can add it to this DEPS file.

  # Chromium git
  "chromium_git": "https://chromium.googlesource.com",
  "fuchsia_git": "https://fuchsia.googlesource.com",

  "co19_2_rev": "9484b81650d8c5bedf72abc541960dd1c90b2329",

  # As Flutter does, we pull buildtools, including the clang toolchain, from
  # Fuchsia. This revision should be kept up to date with the revision pulled
  # by the Flutter engine. If there are problems with the toolchain, contact
  # fuchsia-toolchain@.
  "buildtools_revision": "446d5b1019dcbe7835236dc85261e91cf29a9239",

  # Scripts that make 'git cl format' work.
  "clang_format_scripts_rev": "c09c8deeac31f05bd801995c475e7c8070f9ecda",

  "gperftools_revision": "9608fa3bcf8020d35f59fbf70cd3cbe4b015b972",

  # Revisions of /third_party/* dependencies.
  "args_tag": "1.4.4",
  "async_tag": "2.0.8",
  "bazel_worker_tag": "0.1.14",
  "boolean_selector_tag" : "1.0.4",
  "boringssl_gen_rev": "fc47eaa1a245d858bae462cd64d4155605b850ea",
  "boringssl_rev" : "189270cd190267f5bd60cfe8f8ce7a61d07ba6f4",
  "charcode_tag": "v1.1.2",
  "chrome_rev" : "19997",
  "cli_util_rev" : "4ad7ccbe3195fd2583b30f86a86697ef61e80f41",
  "collection_tag": "1.14.11",
  "convert_tag": "2.0.2",
  "crypto_tag" : "2.0.6",
  "csslib_tag" : "0.14.4+1",
  "dart2js_info_tag" : "0.5.6+4",

  # Note: updates to dart_style have to be coordinated carefully with
  # the infrastructure-team so that the internal formatter in
  # `sdk/tools/sdks/dart-sdk/bin/dartfmt` matches the version here.
  #
  # Please follow this process to make updates:
  #   * file an issue with area-infrastructure requesting a roll for this
  #     package (please also indicate what version to roll).
  #   * let the infrastructure team submit the change on your behalf,
  #     so they can build a new dev release and roll the submitted sdks a few
  #     minutes later.
  #
  # For more details, see https://github.com/dart-lang/sdk/issues/30164
  "dart_style_tag": "1.2.0",  # Please see the note above before updating.

  "dartdoc_tag" : "v0.23.1",
  "file_rev": "515ed1dd48740ab14b625de1be464cb2bca4fefd",  # 5.0.6
  "fixnum_tag": "0.10.8",
  "func_rev": "25eec48146a58967d75330075ab376b3838b18a8",
  "glob_tag": "1.1.7",
  "html_tag" : "0.13.3+2",
  "http_io_rev": "265e90afbffacb7b2988385d4a6aa2f14e970d44",
  "http_multi_server_tag" : "2.0.5",
  "http_parser_tag" : "3.1.1",
  "http_retry_tag": "0.1.1",
  "http_tag" : "0.11.3+17",
  "http_throttle_tag" : "1.0.2",
  "idl_parser_rev": "5fb1ebf49d235b5a70c9f49047e83b0654031eb7",
  "intl_tag": "0.15.7",
  "jinja2_rev": "2222b31554f03e62600cd7e383376a7c187967a1",
  "json_rpc_2_tag": "2.0.9",
  "linter_tag": "0.1.68",
  "logging_tag": "0.11.3+2",
  "markdown_tag": "2.0.2",
  "matcher_tag": "0.12.3",
  "mime_tag": "0.9.6+2",
  "mockito_tag": "d39ac507483b9891165e422ec98d9fb480037c8b",
  "mustache4dart_tag" : "v2.1.2",
  "oauth2_tag": "1.2.1",
  "observatory_pub_packages_rev": "0894122173b0f98eb08863a7712e78407d4477bc",
  "package_config_tag": "1.0.5",
  "package_resolver_tag": "1.0.4",
  "path_tag": "1.6.2",
  "platform_rev": "c368ca95775a4ec8d0b60899ce51299a9fbda399", # 2.2.0
  "plugin_tag": "f5b4b0e32d1406d62daccea030ba6457d14b1c47",
  "ply_rev": "604b32590ffad5cbb82e4afef1d305512d06ae93",
  "pool_tag": "1.3.6",
  "process_rev": "b8d73f0bad7be5ab5130baf10cd042aae4366d7c", # 3.0.5
  "protobuf_tag": "0.9.0",
  "pub_rev": "9f00679ef47bc79cadc18e143720ade6c06c0100",
  "pub_semver_tag": "1.4.2",
  "quiver_tag": "2.0.0+1",
  "resource_rev": "2.1.5",
  "root_certificates_rev": "16ef64be64c7dfdff2b9f4b910726e635ccc519e",
  "shelf_static_rev": "v0.2.8",
  "shelf_packages_handler_tag": "1.0.4",
  "shelf_tag": "0.7.3+3",
  "shelf_web_socket_tag": "0.2.2+3",
  "source_map_stack_trace_tag": "1.1.5",
  "source_maps-0.9.4_rev": "38524",
  "source_maps_tag": "8af7cc1a1c3a193c1fba5993ce22a546a319c40e",
  "source_span_tag": "1.4.1",
  "stack_trace_tag": "1.9.3",
  "stream_channel_tag": "1.6.8",
  "string_scanner_tag": "1.0.3",
  "test_descriptor_tag": "1.1.1",
  "test_process_tag": "1.0.3",
  "term_glyph_tag": "1.0.1",
  "test_reflective_loader_tag": "0.1.8",
  "test_tag": "1.0.0",
  "tuple_tag": "v1.0.1",
  "typed_data_tag": "1.1.6",
  "unittest_rev": "2b8375bc98bb9dc81c539c91aaea6adce12e1072",
  "usage_tag": "3.4.0",
  "utf_tag": "0.9.0+5",
  "watcher_rev": "0.9.7+10",
  "web_components_rev": "8f57dac273412a7172c8ade6f361b407e2e4ed02",
  "web_socket_channel_tag": "1.0.9",
  "WebCore_rev": "fb11e887f77919450e497344da570d780e078bc8",
  "yaml_tag": "2.1.15",
  "zlib_rev": "c3d0a6190f2f8c924a05ab6cc97b8f975bddd33f",
}

deps = {
  # Stuff needed for GN build.
  Var("dart_root") + "/buildtools":
     Var("fuchsia_git") + "/buildtools" + "@" + Var("buildtools_revision"),
  Var("dart_root") + "/buildtools/clang_format/script":
    Var("chromium_git") + "/chromium/llvm-project/cfe/tools/clang-format.git" +
    "@" + Var("clang_format_scripts_rev"),

  Var("dart_root") + "/tools/sdks": {
      "packages": [
          {
              "package": "dart/dart-sdk/${{platform}}",
              "version": "version:2.1.0-dev.6.0",
          },
      ],
      "dep_type": "cipd",
  },
  Var("dart_root") + "/third_party/d8": {
      "packages": [
          {
              "package": "dart/d8",
              "version": "version:6.9.427.23+1",
          },
      ],
      "dep_type": "cipd",
  },

  Var("dart_root") + "/tests/co19_2/src":
      Var("chromium_git") + "/external/github.com/dart-lang/co19.git" +
      "@" + Var("co19_2_rev"),

  Var("dart_root") + "/third_party/zlib":
      Var("chromium_git") + "/chromium/src/third_party/zlib.git" +
      "@" + Var("zlib_rev"),

  Var("dart_root") + "/third_party/boringssl":
      Var("dart_git") + "boringssl_gen.git" + "@" + Var("boringssl_gen_rev"),
  Var("dart_root") + "/third_party/boringssl/src":
      "https://boringssl.googlesource.com/boringssl.git" +
      "@" + Var("boringssl_rev"),

  Var("dart_root") + "/third_party/root_certificates":
      Var("dart_git") + "root_certificates.git" +
      "@" + Var("root_certificates_rev"),

  Var("dart_root") + "/third_party/jinja2":
      Var("chromium_git") + "/chromium/src/third_party/jinja2.git" +
      "@" + Var("jinja2_rev"),

  Var("dart_root") + "/third_party/ply":
      Var("chromium_git") + "/chromium/src/third_party/ply.git" +
      "@" + Var("ply_rev"),

  Var("dart_root") + "/tools/idl_parser":
      Var("chromium_git") + "/chromium/src/tools/idl_parser.git" +
      "@" + Var("idl_parser_rev"),

  Var("dart_root") + "/third_party/WebCore":
      Var("dart_git") + "webcore.git" + "@" + Var("WebCore_rev"),

  Var("dart_root") + "/third_party/tcmalloc/gperftools":
      Var('chromium_git') + '/external/github.com/gperftools/gperftools.git' +
      "@" + Var("gperftools_revision"),

  Var("dart_root") + "/third_party/pkg/args":
      Var("dart_git") + "args.git" + "@" + Var("args_tag"),
  Var("dart_root") + "/third_party/pkg/async":
      Var("dart_git") + "async.git" + "@" + Var("async_tag"),
  Var("dart_root") + "/third_party/pkg/bazel_worker":
      Var("dart_git") + "bazel_worker.git" + "@" + Var("bazel_worker_tag"),
  Var("dart_root") + "/third_party/pkg/boolean_selector":
      Var("dart_git") + "boolean_selector.git" +
      "@" + Var("boolean_selector_tag"),
  Var("dart_root") + "/third_party/pkg/charcode":
      Var("dart_git") + "charcode.git" + "@" + Var("charcode_tag"),
  Var("dart_root") + "/third_party/pkg/cli_util":
      Var("dart_git") + "cli_util.git" + "@" + Var("cli_util_rev"),
  Var("dart_root") + "/third_party/pkg/collection":
      Var("dart_git") + "collection.git" + "@" + Var("collection_tag"),
  Var("dart_root") + "/third_party/pkg/convert":
      Var("dart_git") + "convert.git" + "@" + Var("convert_tag"),
  Var("dart_root") + "/third_party/pkg/crypto":
      Var("dart_git") + "crypto.git" + "@" + Var("crypto_tag"),
  Var("dart_root") + "/third_party/pkg/csslib":
      Var("dart_git") + "csslib.git" + "@" + Var("csslib_tag"),
  Var("dart_root") + "/third_party/pkg_tested/dart_style":
      Var("dart_git") + "dart_style.git" + "@" + Var("dart_style_tag"),
  Var("dart_root") + "/third_party/pkg/dart2js_info":
      Var("dart_git") + "dart2js_info.git" + "@" + Var("dart2js_info_tag"),
  Var("dart_root") + "/third_party/pkg/dartdoc":
      Var("dart_git") + "dartdoc.git" + "@" + Var("dartdoc_tag"),
  Var("dart_root") + "/third_party/pkg/file":
      Var("dart_git") + "file.dart.git" + "@" + Var("file_rev"),
  Var("dart_root") + "/third_party/pkg/fixnum":
      Var("dart_git") + "fixnum.git" + "@" + Var("fixnum_tag"),
  Var("dart_root") + "/third_party/pkg/func":
      Var("dart_git") + "func.git" + "@" + Var("func_rev"),
  Var("dart_root") + "/third_party/pkg/glob":
      Var("dart_git") + "glob.git" + "@" + Var("glob_tag"),
  Var("dart_root") + "/third_party/pkg/html":
      Var("dart_git") + "html.git" + "@" + Var("html_tag"),
  Var("dart_root") + "/third_party/pkg/http":
      Var("dart_git") + "http.git" + "@" + Var("http_tag"),
  Var("dart_root") + "/third_party/pkg_tested/http_io":
    Var("dart_git") + "http_io.git" + "@" + Var("http_io_rev"),
  Var("dart_root") + "/third_party/pkg/http_multi_server":
      Var("dart_git") + "http_multi_server.git" +
      "@" + Var("http_multi_server_tag"),
  Var("dart_root") + "/third_party/pkg/http_parser":
      Var("dart_git") + "http_parser.git" + "@" + Var("http_parser_tag"),
  Var("dart_root") + "/third_party/pkg/http_retry":
      Var("dart_git") + "http_retry.git" +
      "@" + Var("http_retry_tag"),
  Var("dart_root") + "/third_party/pkg/http_throttle":
      Var("dart_git") + "http_throttle.git" +
      "@" + Var("http_throttle_tag"),
  Var("dart_root") + "/third_party/pkg/intl":
      Var("dart_git") + "intl.git" + "@" + Var("intl_tag"),
  Var("dart_root") + "/third_party/pkg/json_rpc_2":
      Var("dart_git") + "json_rpc_2.git" + "@" + Var("json_rpc_2_tag"),
  Var("dart_root") + "/third_party/pkg/linter":
      Var("dart_git") + "linter.git" + "@" + Var("linter_tag"),
  Var("dart_root") + "/third_party/pkg/logging":
      Var("dart_git") + "logging.git" + "@" + Var("logging_tag"),
  Var("dart_root") + "/third_party/pkg/markdown":
      Var("dart_git") + "markdown.git" + "@" + Var("markdown_tag"),
  Var("dart_root") + "/third_party/pkg/matcher":
      Var("dart_git") + "matcher.git" + "@" + Var("matcher_tag"),
  Var("dart_root") + "/third_party/pkg/mime":
      Var("dart_git") + "mime.git" + "@" + Var("mime_tag"),
  Var("dart_root") + "/third_party/pkg/mockito":
      Var("dart_git") + "mockito.git" + "@" + Var("mockito_tag"),
  Var("dart_root") + "/third_party/pkg/mustache4dart":
      Var("chromium_git")
      + "/external/github.com/valotas/mustache4dart.git"
      + "@" + Var("mustache4dart_tag"),
  Var("dart_root") + "/third_party/pkg/oauth2":
      Var("dart_git") + "oauth2.git" + "@" + Var("oauth2_tag"),
  Var("dart_root") + "/third_party/observatory_pub_packages":
      Var("dart_git") + "observatory_pub_packages.git"
      + "@" + Var("observatory_pub_packages_rev"),
  Var("dart_root") + "/third_party/pkg_tested/package_config":
      Var("dart_git") + "package_config.git" +
      "@" + Var("package_config_tag"),
  Var("dart_root") + "/third_party/pkg_tested/package_resolver":
      Var("dart_git") + "package_resolver.git"
      + "@" + Var("package_resolver_tag"),
  Var("dart_root") + "/third_party/pkg/path":
      Var("dart_git") + "path.git" + "@" + Var("path_tag"),
  Var("dart_root") + "/third_party/pkg/platform":
      Var("dart_git") + "platform.dart.git" + "@" + Var("platform_rev"),
  Var("dart_root") + "/third_party/pkg/plugin":
      Var("dart_git") + "plugin.git" + "@" + Var("plugin_tag"),
  Var("dart_root") + "/third_party/pkg/pool":
      Var("dart_git") + "pool.git" + "@" + Var("pool_tag"),
  Var("dart_root") + "/third_party/pkg/process":
      Var("dart_git") + "process.dart.git" + "@" + Var("process_rev"),
  Var("dart_root") + "/third_party/pkg/protobuf":
      Var("dart_git") + "protobuf.git" + "@" + Var("protobuf_tag"),
  Var("dart_root") + "/third_party/pkg/pub_semver":
      Var("dart_git") + "pub_semver.git" + "@" + Var("pub_semver_tag"),
  Var("dart_root") + "/third_party/pkg/pub":
      Var("dart_git") + "pub.git" + "@" + Var("pub_rev"),
  Var("dart_root") + "/third_party/pkg/quiver":
      Var("chromium_git")
      + "/external/github.com/google/quiver-dart.git"
      + "@" + Var("quiver_tag"),
  Var("dart_root") + "/third_party/pkg/resource":
      Var("dart_git") + "resource.git" + "@" + Var("resource_rev"),
  Var("dart_root") + "/third_party/pkg/shelf":
      Var("dart_git") + "shelf.git" + "@" + Var("shelf_tag"),
  Var("dart_root") + "/third_party/pkg/shelf_packages_handler":
      Var("dart_git") + "shelf_packages_handler.git"
      + "@" + Var("shelf_packages_handler_tag"),
  Var("dart_root") + "/third_party/pkg/shelf_static":
      Var("dart_git") + "shelf_static.git" + "@" + Var("shelf_static_rev"),
  Var("dart_root") + "/third_party/pkg/shelf_web_socket":
      Var("dart_git") + "shelf_web_socket.git" +
      "@" + Var("shelf_web_socket_tag"),
  Var("dart_root") + "/third_party/pkg/source_maps":
      Var("dart_git") + "source_maps.git" + "@" + Var("source_maps_tag"),
  Var("dart_root") + "/third_party/pkg/source_span":
      Var("dart_git") + "source_span.git" + "@" + Var("source_span_tag"),
  Var("dart_root") + "/third_party/pkg/source_map_stack_trace":
      Var("dart_git") + "source_map_stack_trace.git" +
      "@" + Var("source_map_stack_trace_tag"),
  Var("dart_root") + "/third_party/pkg/stack_trace":
      Var("dart_git") + "stack_trace.git" + "@" + Var("stack_trace_tag"),
  Var("dart_root") + "/third_party/pkg/stream_channel":
      Var("dart_git") + "stream_channel.git" +
      "@" + Var("stream_channel_tag"),
  Var("dart_root") + "/third_party/pkg/string_scanner":
      Var("dart_git") + "string_scanner.git" +
      "@" + Var("string_scanner_tag"),
  Var("dart_root") + "/third_party/pkg/term_glyph":
      Var("dart_git") + "term_glyph.git" + "@" + Var("term_glyph_tag"),
  Var("dart_root") + "/third_party/pkg/test":
      Var("dart_git") + "test.git" + "@" + Var("test_tag"),
  Var("dart_root") + "/third_party/pkg/test_descriptor":
      Var("dart_git") + "test_descriptor.git" + "@" + Var("test_descriptor_tag"),
  Var("dart_root") + "/third_party/pkg/test_process":
      Var("dart_git") + "test_process.git" + "@" + Var("test_process_tag"),
  Var("dart_root") + "/third_party/pkg/test_reflective_loader":
      Var("dart_git") + "test_reflective_loader.git" +
      "@" + Var("test_reflective_loader_tag"),
  Var("dart_root") + "/third_party/pkg/tuple":
      Var("dart_git") + "tuple.git" + "@" + Var("tuple_tag"),
  Var("dart_root") + "/third_party/pkg/typed_data":
      Var("dart_git") + "typed_data.git" + "@" + Var("typed_data_tag"),
  # Unittest is an early version, 0.11.x, of the package "test"
  # Do not use it in any new tests. Fetched from chromium_git to avoid
  # race condition in cache with pkg/test.
  Var("dart_root") + "/third_party/pkg/unittest":
      Var("chromium_git") + "/external/github.com/dart-lang/test.git" +
      "@" + Var("unittest_rev"),
  Var("dart_root") + "/third_party/pkg/usage":
      Var("dart_git") + "usage.git" + "@" + Var("usage_tag"),
  Var("dart_root") + "/third_party/pkg/utf":
      Var("dart_git") + "utf.git" + "@" + Var("utf_tag"),
  Var("dart_root") + "/third_party/pkg/watcher":
      Var("dart_git") + "watcher.git" + "@" + Var("watcher_rev"),
  Var("dart_root") + "/third_party/pkg/web_components":
      Var("dart_git") + "web-components.git" +
      "@" + Var("web_components_rev"),
  Var("dart_root") + "/third_party/pkg/web_socket_channel":
      Var("dart_git") + "web_socket_channel.git" +
      "@" + Var("web_socket_channel_tag"),
  Var("dart_root") + "/third_party/pkg/yaml":
      Var("dart_git") + "yaml.git" + "@" + Var("yaml_tag"),
  Var("dart_root") + "/third_party/cygwin": {
    "url": Var("chromium_git") + "/chromium/deps/cygwin.git" + "@" +
        "c89e446b273697fadf3a10ff1007a97c0b7de6df",
    "condition": "checkout_win",
  },
}

# TODO(iposva): Move the necessary tools so that hooks can be run
# without the runtime being available.
hooks = [
  {
    "name": "firefox_jsshell",
    "pattern": ".",
    "action": [
      "download_from_google_storage",
      "--no_auth",
      "--no_resume",
      "--bucket",
      "dart-dependencies",
      "--recursive",
      "--auto_platform",
      "--extract",
      "--directory",
      Var('dart_root') + "/third_party/firefox_jsshell",
    ],
  },
  {
    "name": "7zip",
    "pattern": ".",
    "action": [
      "download_from_google_storage",
      "--no_auth",
      "--no_resume",
      "--bucket",
      "dart-dependencies",
      "--platform=win32",
      "--extract",
      "-s",
      Var('dart_root') + "/third_party/7zip.tar.gz.sha1",
    ],
  },
  {
    "name": "gsutil",
    "pattern": ".",
    "action": [
      "download_from_google_storage",
      "--no_auth",
      "--no_resume",
      "--bucket",
      "dart-dependencies",
      "--extract",
      "-s",
      Var('dart_root') + "/third_party/gsutil.tar.gz.sha1",
    ],
  },
  {
    # Pull Debian wheezy sysroot for i386 Linux
    'name': 'sysroot_i386',
    'pattern': '.',
    'action': ['python', 'sdk/build/linux/sysroot_scripts/install-sysroot.py',
               '--arch', 'i386'],
  },
  {
    # Pull Debian wheezy sysroot for amd64 Linux
    'name': 'sysroot_amd64',
    'pattern': '.',
    'action': ['python', 'sdk/build/linux/sysroot_scripts/install-sysroot.py',
               '--arch', 'amd64'],
  },
  {
    # Pull Debian wheezy sysroot for arm Linux
    'name': 'sysroot_amd64',
    'pattern': '.',
    'action': ['python', 'sdk/build/linux/sysroot_scripts/install-sysroot.py',
               '--arch', 'arm'],
  },
  {
    # Pull Debian jessie sysroot for arm64 Linux
    'name': 'sysroot_amd64',
    'pattern': '.',
    'action': ['python', 'sdk/build/linux/sysroot_scripts/install-sysroot.py',
               '--arch', 'arm64'],
  },
  {
    'name': 'download_android_tools',
    'pattern': '.',
    'action': ['python', 'sdk/tools/android/download_android_tools.py'],
  },
  {
    'name': 'buildtools',
    'pattern': '.',
    'action': ['python', 'sdk/tools/buildtools/update.py'],
  },
  {
    # Update the Windows toolchain if necessary.
    'name': 'win_toolchain',
    'pattern': '.',
    'action': ['python', 'sdk/build/vs_toolchain.py', 'update'],
  },
]
