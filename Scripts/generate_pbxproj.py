#!/usr/bin/env python3
"""
Generates ProjectStock.xcodeproj/project.pbxproj by scanning the source tree.

This is a small, purpose-built project generator (think "tiny XcodeGen"). It is
deterministic: every object id is derived from a stable string so re-running it
produces an identical file. Run it from the repository root:

    python3 Scripts/generate_pbxproj.py

It creates three targets:
  * ProjectStock           (iOS app)
  * ProjectStockTests      (unit tests, hosted by the app)
  * ProjectStockUITests    (UI tests)

System frameworks (CloudKit, CoreData, AVFoundation, …) are linked implicitly
by Swift autolinking, so no explicit framework references are needed.
"""

import os
import hashlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_DIR = "ProjectStock"
TEST_DIR = "ProjectStockTests"
UITEST_DIR = "ProjectStockUITests"

def oid(*parts):
    """Stable 24-hex-char object id from the given key parts."""
    h = hashlib.md5("::".join(parts).encode("utf-8")).hexdigest().upper()
    return h[:24]

objects = {}          # id -> body string
app_sources = []      # build file ids
test_sources = []
uitest_sources = []
app_resources = []    # build file ids

def add_object(obj_id, body):
    objects[obj_id] = body

def file_type(path):
    if path.endswith(".swift"): return "sourcecode.swift"
    if path.endswith(".plist"): return "text.plist.xml"
    if path.endswith(".entitlements"): return "text.plist.entitlements"
    if path.endswith(".xcassets"): return "folder.assetcatalog"
    if path.endswith(".md"): return "net.daringfireball.markdown"
    if path.endswith(".xcconfig"): return "text.xcconfig"
    if path.endswith(".json"): return "text.json"
    return "text"

def make_file_ref(path_rel, name):
    fid = oid("fileref", path_rel)
    ft = file_type(name)
    add_object(fid, (
        f"{fid} /* {name} */ = {{isa = PBXFileReference; "
        f"lastKnownFileType = {ft}; path = \"{name}\"; sourceTree = \"<group>\"; }};"
    ))
    return fid

def make_build_file(file_ref, name, key):
    # Key on the unique file reference so basename collisions can't merge entries.
    bid = oid("buildfile", key, file_ref)
    add_object(bid, f"{bid} /* {name} in Build */ = {{isa = PBXBuildFile; fileRef = {file_ref} /* {name} */; }};")
    return bid

def make_datamodel(dir_abs, dir_rel, name):
    """XCVersionGroup for a .xcdatamodeld bundle."""
    versions = [c for c in sorted(os.listdir(dir_abs)) if c.endswith(".xcdatamodel")]
    child_ids = []
    current = None
    for v in versions:
        vid = oid("xcdatamodel", os.path.join(dir_rel, v))
        add_object(vid, (
            f"{vid} /* {v} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = wrapper.xcdatamodel; path = \"{v}\"; sourceTree = \"<group>\"; }};"
        ))
        child_ids.append((vid, v))
        if v == "ProjectStock.xcdatamodel":
            current = vid
    if current is None and child_ids:
        current = child_ids[0][0]
    gid = oid("xcversiongroup", dir_rel)
    children = "\n\t\t\t\t".join(f"{cid} /* {cname} */," for cid, cname in child_ids)
    add_object(gid, (
        f"{gid} /* {name} */ = {{\n"
        f"\t\t\tisa = XCVersionGroup;\n"
        f"\t\t\tchildren = (\n\t\t\t\t{children}\n\t\t\t);\n"
        f"\t\t\tcurrentVersion = {current} /* ProjectStock.xcdatamodel */;\n"
        f"\t\t\tpath = \"{name}\";\n"
        f"\t\t\tsourceTree = \"<group>\";\n"
        f"\t\t\tversionGroupType = wrapper.xcdatamodel;\n"
        f"\t\t}};"
    ))
    return gid

def make_variant_group(dir_abs, dir_rel, strings_name):
    """
    Collect all <lang>.lproj/<strings_name> files under dir_abs and emit a
    PBXVariantGroup named strings_name.  Returns the variant-group id so the
    caller can add it to a PBXResourcesBuildPhase.
    """
    lang_entries = []
    for entry in sorted(os.listdir(dir_abs)):
        if not entry.endswith(".lproj"):
            continue
        abs_lproj = os.path.join(dir_abs, entry)
        if not os.path.isdir(abs_lproj):
            continue
        strings_path = os.path.join(abs_lproj, strings_name)
        if not os.path.isfile(strings_path):
            continue
        lang = entry[:-len(".lproj")]          # e.g. "ja", "en", "Base"
        rel_strings = os.path.join(dir_rel, entry, strings_name)
        fid = oid("fileref", rel_strings)
        add_object(fid, (
            f"{fid} /* {lang} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = text.plist.strings; "
            f"name = \"{lang}\"; "
            f"path = \"{entry}/{strings_name}\"; "
            f"sourceTree = \"<group>\"; }};"
        ))
        lang_entries.append((fid, lang))

    if not lang_entries:
        return None

    vgid = oid("variantgroup", os.path.join(dir_rel, strings_name))
    kids = "\n\t\t\t\t".join(f"{fid} /* {lang} */," for fid, lang in lang_entries)
    add_object(vgid, (
        f"{vgid} /* {strings_name} */ = {{\n"
        f"\t\t\tisa = PBXVariantGroup;\n"
        f"\t\t\tchildren = (\n\t\t\t\t{kids}\n\t\t\t);\n"
        f"\t\t\tname = \"{strings_name}\";\n"
        f"\t\t\tsourceTree = \"<group>\";\n"
        f"\t\t}};"
    ))
    return vgid


def build_group(dir_abs, dir_rel, target):
    """Recursively create a PBXGroup for a directory; returns (group_id, name)."""
    name = os.path.basename(dir_rel)
    children = []

    # --- Pre-scan: collect all *.strings files living inside *.lproj dirs,
    #     grouped by their basename, so we can emit one PBXVariantGroup each. ---
    lproj_strings = set()   # basenames like "Localizable.strings"
    lproj_dirs = set()      # entry names like "en.lproj"
    for entry in os.listdir(dir_abs):
        if entry.endswith(".lproj") and os.path.isdir(os.path.join(dir_abs, entry)):
            lproj_dirs.add(entry)
            lproj_abs = os.path.join(dir_abs, entry)
            for f in os.listdir(lproj_abs):
                if f.endswith(".strings"):
                    lproj_strings.add(f)

    # Emit one PBXVariantGroup per distinct strings filename, add to resources.
    variant_group_ids = {}   # strings_name -> vgid
    for sname in sorted(lproj_strings):
        vgid = make_variant_group(dir_abs, dir_rel, sname)
        if vgid:
            variant_group_ids[sname] = vgid
            children.append((vgid, sname))
            if target == "app":
                bid = make_build_file(vgid, sname, "app-res-variant-" + sname)
                app_resources.append(bid)

    for entry in sorted(os.listdir(dir_abs)):
        if entry.startswith("."):
            continue
        # Skip .lproj dirs — already handled above as variant groups.
        if entry in lproj_dirs:
            continue
        abs_e = os.path.join(dir_abs, entry)
        rel_e = os.path.join(dir_rel, entry)
        if os.path.isdir(abs_e):
            if entry.endswith(".xcdatamodeld"):
                gid = make_datamodel(abs_e, rel_e, entry)
                children.append((gid, entry))
                bid = make_build_file(gid, entry, "app")
                app_sources.append(bid)
            elif entry.endswith(".xcassets"):
                fid = make_file_ref(rel_e, entry)
                children.append((fid, entry))
                bid = make_build_file(fid, entry, "app-res")
                app_resources.append(bid)
            else:
                gid, _ = build_group(abs_e, rel_e, target)
                children.append((gid, entry))
        else:
            fid = make_file_ref(rel_e, entry)
            children.append((fid, entry))
            if entry.endswith(".swift"):
                bid = make_build_file(fid, entry, target)
                if target == "app": app_sources.append(bid)
                elif target == "test": test_sources.append(bid)
                elif target == "uitest": uitest_sources.append(bid)
            # Info.plist / entitlements are referenced via build settings, not phases.
    gid = oid("group", dir_rel)
    kids = "\n\t\t\t\t".join(f"{cid} /* {cname} */," for cid, cname in children)
    add_object(gid, (
        f"{gid} /* {name} */ = {{\n"
        f"\t\t\tisa = PBXGroup;\n"
        f"\t\t\tchildren = (\n\t\t\t\t{kids}\n\t\t\t);\n"
        f"\t\t\tpath = \"{name}\";\n"
        f"\t\t\tsourceTree = \"<group>\";\n"
        f"\t\t}};"
    ))
    return gid, name

# --- Build groups for each target -------------------------------------------
app_group, _ = build_group(os.path.join(ROOT, APP_DIR), APP_DIR, "app")
test_group, _ = build_group(os.path.join(ROOT, TEST_DIR), TEST_DIR, "test")
uitest_group, _ = build_group(os.path.join(ROOT, UITEST_DIR), UITEST_DIR, "uitest")

# --- Documentation group (not built) ----------------------------------------
doc_children = []
for entry in sorted(os.listdir(ROOT)):
    if entry.endswith(".md") or entry == "Config.xcconfig.example":
        fid = make_file_ref(entry, entry)
        doc_children.append((fid, entry))
doc_group = oid("group", "Documentation")
doc_kids = "\n\t\t\t\t".join(f"{cid} /* {cname} */," for cid, cname in doc_children)
add_object(doc_group, (
    f"{doc_group} /* Documentation */ = {{\n"
    f"\t\t\tisa = PBXGroup;\n"
    f"\t\t\tchildren = (\n\t\t\t\t{doc_kids}\n\t\t\t);\n"
    f"\t\t\tname = Documentation;\n"
    f"\t\t\tsourceTree = \"<group>\";\n"
    f"\t\t}};"
))

# --- Products group ----------------------------------------------------------
app_product = oid("product", "app")
test_product = oid("product", "test")
uitest_product = oid("product", "uitest")
add_object(app_product, f"{app_product} /* ProjectStock.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = ProjectStock.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
add_object(test_product, f"{test_product} /* ProjectStockTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = ProjectStockTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")
add_object(uitest_product, f"{uitest_product} /* ProjectStockUITests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = ProjectStockUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")
products_group = oid("group", "Products")
add_object(products_group, (
    f"{products_group} /* Products */ = {{\n"
    f"\t\t\tisa = PBXGroup;\n"
    f"\t\t\tchildren = (\n\t\t\t\t{app_product} /* ProjectStock.app */,\n\t\t\t\t{test_product} /* ProjectStockTests.xctest */,\n\t\t\t\t{uitest_product} /* ProjectStockUITests.xctest */,\n\t\t\t);\n"
    f"\t\t\tname = Products;\n"
    f"\t\t\tsourceTree = \"<group>\";\n"
    f"\t\t}};"
))

# --- Main group --------------------------------------------------------------
main_group = oid("group", "main")
add_object(main_group, (
    f"{main_group} = {{\n"
    f"\t\t\tisa = PBXGroup;\n"
    f"\t\t\tchildren = (\n"
    f"\t\t\t\t{app_group} /* ProjectStock */,\n"
    f"\t\t\t\t{test_group} /* ProjectStockTests */,\n"
    f"\t\t\t\t{uitest_group} /* ProjectStockUITests */,\n"
    f"\t\t\t\t{doc_group} /* Documentation */,\n"
    f"\t\t\t\t{products_group} /* Products */,\n"
    f"\t\t\t);\n"
    f"\t\t\tsourceTree = \"<group>\";\n"
    f"\t\t}};"
))

# --- Build phases ------------------------------------------------------------
def phase(phase_id, isa, name, files):
    body_files = "\n\t\t\t\t".join(f"{f} /* in {name} */," for f in files)
    return (
        f"{phase_id} /* {name} */ = {{\n"
        f"\t\t\tisa = {isa};\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n\t\t\t\t{body_files}\n\t\t\t);\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};"
    )

app_sources_phase = oid("phase", "app-sources")
app_resources_phase = oid("phase", "app-resources")
app_frameworks_phase = oid("phase", "app-frameworks")
test_sources_phase = oid("phase", "test-sources")
test_frameworks_phase = oid("phase", "test-frameworks")
uitest_sources_phase = oid("phase", "uitest-sources")
uitest_frameworks_phase = oid("phase", "uitest-frameworks")

add_object(app_sources_phase, phase(app_sources_phase, "PBXSourcesBuildPhase", "Sources", app_sources))
add_object(app_resources_phase, phase(app_resources_phase, "PBXResourcesBuildPhase", "Resources", app_resources))
add_object(app_frameworks_phase, phase(app_frameworks_phase, "PBXFrameworksBuildPhase", "Frameworks", []))
add_object(test_sources_phase, phase(test_sources_phase, "PBXSourcesBuildPhase", "Sources", test_sources))
add_object(test_frameworks_phase, phase(test_frameworks_phase, "PBXFrameworksBuildPhase", "Frameworks", []))
add_object(uitest_sources_phase, phase(uitest_sources_phase, "PBXSourcesBuildPhase", "Sources", uitest_sources))
add_object(uitest_frameworks_phase, phase(uitest_frameworks_phase, "PBXFrameworksBuildPhase", "Frameworks", []))

# --- Target dependencies -----------------------------------------------------
project_id = oid("project", "ProjectStock")
app_target = oid("target", "app")
test_target = oid("target", "test")
uitest_target = oid("target", "uitest")

def dependency(dep_key, target_id, target_name):
    proxy_id = oid("proxy", dep_key)
    dep_id = oid("dependency", dep_key)
    add_object(proxy_id, (
        f"{proxy_id} /* PBXContainerItemProxy */ = {{\n"
        f"\t\t\tisa = PBXContainerItemProxy;\n"
        f"\t\t\tcontainerPortal = {project_id} /* Project object */;\n"
        f"\t\t\tproxyType = 1;\n"
        f"\t\t\tremoteGlobalIDString = {target_id};\n"
        f"\t\t\tremoteInfo = {target_name};\n"
        f"\t\t}};"
    ))
    add_object(dep_id, (
        f"{dep_id} /* PBXTargetDependency */ = {{\n"
        f"\t\t\tisa = PBXTargetDependency;\n"
        f"\t\t\ttarget = {target_id} /* {target_name} */;\n"
        f"\t\t\ttargetProxy = {proxy_id} /* PBXContainerItemProxy */;\n"
        f"\t\t}};"
    ))
    return dep_id

test_dep = dependency("test-on-app", app_target, "ProjectStock")
uitest_dep = dependency("uitest-on-app", app_target, "ProjectStock")

# --- Build configurations ----------------------------------------------------
def settings_block(d):
    lines = []
    for k in sorted(d.keys()):
        v = d[k]
        if isinstance(v, list):
            inner = "".join(f"\n\t\t\t\t\t\"{item}\"," for item in v)
            lines.append(f"\t\t\t\t{k} = ({inner}\n\t\t\t\t);")
        else:
            lines.append(f"\t\t\t\t{k} = {v};")
    return "\n".join(lines)

def build_config(cfg_id, name, settings):
    add_object(cfg_id, (
        f"{cfg_id} /* {name} */ = {{\n"
        f"\t\t\tisa = XCBuildConfiguration;\n"
        f"\t\t\tbuildSettings = {{\n{settings_block(settings)}\n\t\t\t}};\n"
        f"\t\t\tname = {name};\n"
        f"\t\t}};"
    ))

PROJECT_COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu11",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "15.0",
    "MTL_FAST_MATH": "YES",
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1",
    "ENABLE_BITCODE": "NO",
}

PROJECT_DEBUG = dict(PROJECT_COMMON, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
})

PROJECT_RELEASE = dict(PROJECT_COMMON, **{
    "DEBUG_INFORMATION_FORMAT": "\"dwarf-with-dsym\"",
    "ENABLE_NS_ASSERTIONS": "NO",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL": "\"-O\"",
    "VALIDATE_PRODUCT": "YES",
})

APP_COMMON = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "ProjectStock/App/ProjectStock.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": "\"\"",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "ProjectStock/App/Info.plist",
    "APP_DISPLAY_NAME": "タナミル",
    "CLOUDKIT_CONTAINER_IDENTIFIER": "iCloud.com.tenten.tanamiru",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "MARKETING_VERSION": "1.0.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.tenten.tanamiru",
    "PRODUCT_NAME": "\"$(TARGET_NAME)\"",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "TARGETED_DEVICE_FAMILY": "1",
}

TEST_COMMON = {
    "BUNDLE_LOADER": "\"$(TEST_HOST)\"",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": "\"\"",
    "GENERATE_INFOPLIST_FILE": "YES",
    "MARKETING_VERSION": "1.0.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.tenten.tanamiru.tests",
    "PRODUCT_NAME": "\"$(TARGET_NAME)\"",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1",
    "TEST_HOST": "\"$(BUILT_PRODUCTS_DIR)/ProjectStock.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/ProjectStock\"",
}

UITEST_COMMON = {
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": "\"\"",
    "GENERATE_INFOPLIST_FILE": "YES",
    "MARKETING_VERSION": "1.0.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.tenten.tanamiru.uitests",
    "PRODUCT_NAME": "\"$(TARGET_NAME)\"",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1",
    "TEST_TARGET_NAME": "ProjectStock",
}

cfg_proj_debug = oid("cfg", "proj-debug"); build_config(cfg_proj_debug, "Debug", PROJECT_DEBUG)
cfg_proj_release = oid("cfg", "proj-release"); build_config(cfg_proj_release, "Release", PROJECT_RELEASE)
cfg_app_debug = oid("cfg", "app-debug"); build_config(cfg_app_debug, "Debug", APP_COMMON)
cfg_app_release = oid("cfg", "app-release"); build_config(cfg_app_release, "Release", APP_COMMON)
cfg_test_debug = oid("cfg", "test-debug"); build_config(cfg_test_debug, "Debug", TEST_COMMON)
cfg_test_release = oid("cfg", "test-release"); build_config(cfg_test_release, "Release", TEST_COMMON)
cfg_uitest_debug = oid("cfg", "uitest-debug"); build_config(cfg_uitest_debug, "Debug", UITEST_COMMON)
cfg_uitest_release = oid("cfg", "uitest-release"); build_config(cfg_uitest_release, "Release", UITEST_COMMON)

def config_list(list_id, name, debug_id, release_id):
    add_object(list_id, (
        f"{list_id} /* Build configuration list for {name} */ = {{\n"
        f"\t\t\tisa = XCConfigurationList;\n"
        f"\t\t\tbuildConfigurations = (\n\t\t\t\t{debug_id} /* Debug */,\n\t\t\t\t{release_id} /* Release */,\n\t\t\t);\n"
        f"\t\t\tdefaultConfigurationIsVisible = 0;\n"
        f"\t\t\tdefaultConfigurationName = Release;\n"
        f"\t\t}};"
    ))

list_project = oid("cfglist", "project"); config_list(list_project, "PBXProject", cfg_proj_debug, cfg_proj_release)
list_app = oid("cfglist", "app"); config_list(list_app, "ProjectStock", cfg_app_debug, cfg_app_release)
list_test = oid("cfglist", "test"); config_list(list_test, "ProjectStockTests", cfg_test_debug, cfg_test_release)
list_uitest = oid("cfglist", "uitest"); config_list(list_uitest, "ProjectStockUITests", cfg_uitest_debug, cfg_uitest_release)

# --- Native targets ----------------------------------------------------------
add_object(app_target, (
    f"{app_target} /* ProjectStock */ = {{\n"
    f"\t\t\tisa = PBXNativeTarget;\n"
    f"\t\t\tbuildConfigurationList = {list_app} /* Build configuration list for ProjectStock */;\n"
    f"\t\t\tbuildPhases = (\n\t\t\t\t{app_sources_phase} /* Sources */,\n\t\t\t\t{app_frameworks_phase} /* Frameworks */,\n\t\t\t\t{app_resources_phase} /* Resources */,\n\t\t\t);\n"
    f"\t\t\tbuildRules = (\n\t\t\t);\n"
    f"\t\t\tdependencies = (\n\t\t\t);\n"
    f"\t\t\tname = ProjectStock;\n"
    f"\t\t\tproductName = ProjectStock;\n"
    f"\t\t\tproductReference = {app_product} /* ProjectStock.app */;\n"
    f"\t\t\tproductType = \"com.apple.product-type.application\";\n"
    f"\t\t}};"
))
add_object(test_target, (
    f"{test_target} /* ProjectStockTests */ = {{\n"
    f"\t\t\tisa = PBXNativeTarget;\n"
    f"\t\t\tbuildConfigurationList = {list_test} /* Build configuration list for ProjectStockTests */;\n"
    f"\t\t\tbuildPhases = (\n\t\t\t\t{test_sources_phase} /* Sources */,\n\t\t\t\t{test_frameworks_phase} /* Frameworks */,\n\t\t\t);\n"
    f"\t\t\tbuildRules = (\n\t\t\t);\n"
    f"\t\t\tdependencies = (\n\t\t\t\t{test_dep} /* PBXTargetDependency */,\n\t\t\t);\n"
    f"\t\t\tname = ProjectStockTests;\n"
    f"\t\t\tproductName = ProjectStockTests;\n"
    f"\t\t\tproductReference = {test_product} /* ProjectStockTests.xctest */;\n"
    f"\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";\n"
    f"\t\t}};"
))
add_object(uitest_target, (
    f"{uitest_target} /* ProjectStockUITests */ = {{\n"
    f"\t\t\tisa = PBXNativeTarget;\n"
    f"\t\t\tbuildConfigurationList = {list_uitest} /* Build configuration list for ProjectStockUITests */;\n"
    f"\t\t\tbuildPhases = (\n\t\t\t\t{uitest_sources_phase} /* Sources */,\n\t\t\t\t{uitest_frameworks_phase} /* Frameworks */,\n\t\t\t);\n"
    f"\t\t\tbuildRules = (\n\t\t\t);\n"
    f"\t\t\tdependencies = (\n\t\t\t\t{uitest_dep} /* PBXTargetDependency */,\n\t\t\t);\n"
    f"\t\t\tname = ProjectStockUITests;\n"
    f"\t\t\tproductName = ProjectStockUITests;\n"
    f"\t\t\tproductReference = {uitest_product} /* ProjectStockUITests.xctest */;\n"
    f"\t\t\tproductType = \"com.apple.product-type.bundle.ui-testing\";\n"
    f"\t\t}};"
))

# --- Project object ----------------------------------------------------------
add_object(project_id, (
    f"{project_id} /* Project object */ = {{\n"
    f"\t\t\tisa = PBXProject;\n"
    f"\t\t\tattributes = {{\n"
    f"\t\t\t\tBuildIndependentTargetsInParallel = YES;\n"
    f"\t\t\t\tLastSwiftUpdateCheck = 2600;\n"
    f"\t\t\t\tLastUpgradeCheck = 2600;\n"
    f"\t\t\t\tTargetAttributes = {{\n"
    f"\t\t\t\t\t{app_target} = {{CreatedOnToolsVersion = 26.0; }};\n"
    f"\t\t\t\t\t{test_target} = {{CreatedOnToolsVersion = 26.0; TestTargetID = {app_target}; }};\n"
    f"\t\t\t\t\t{uitest_target} = {{CreatedOnToolsVersion = 26.0; TestTargetID = {app_target}; }};\n"
    f"\t\t\t\t}};\n"
    f"\t\t\t}};\n"
    f"\t\t\tbuildConfigurationList = {list_project} /* Build configuration list for PBXProject */;\n"
    f"\t\t\tcompatibilityVersion = \"Xcode 14.0\";\n"
    f"\t\t\tdevelopmentRegion = en;\n"
    f"\t\t\thasScannedForEncodings = 0;\n"
    f"\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tja,\n\t\t\t\tBase,\n\t\t\t);\n"
    f"\t\t\tmainGroup = {main_group};\n"
    f"\t\t\tproductRefGroup = {products_group} /* Products */;\n"
    f"\t\t\tprojectDirPath = \"\";\n"
    f"\t\t\tprojectRoot = \"\";\n"
    f"\t\t\ttargets = (\n\t\t\t\t{app_target} /* ProjectStock */,\n\t\t\t\t{test_target} /* ProjectStockTests */,\n\t\t\t\t{uitest_target} /* ProjectStockUITests */,\n\t\t\t);\n"
    f"\t\t}};"
))

# --- Emit --------------------------------------------------------------------
out = []
out.append("// !$*UTF8*$!")
out.append("{")
out.append("\tarchiveVersion = 1;")
out.append("\tclasses = {")
out.append("\t};")
out.append("\tobjectVersion = 56;")
out.append("\tobjects = {")
for obj_id in sorted(objects.keys()):
    out.append("\t\t" + objects[obj_id])
out.append("\t};")
out.append(f"\trootObject = {project_id} /* Project object */;")
out.append("}")

proj_dir = os.path.join(ROOT, "ProjectStock.xcodeproj")
os.makedirs(proj_dir, exist_ok=True)
with open(os.path.join(proj_dir, "project.pbxproj"), "w") as f:
    f.write("\n".join(out) + "\n")

print(f"Wrote {os.path.join(proj_dir, 'project.pbxproj')}")
print(f"  app sources: {len(app_sources)}  resources: {len(app_resources)}")
print(f"  test sources: {len(test_sources)}  uitest sources: {len(uitest_sources)}")
