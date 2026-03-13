#!/usr/bin/env python3
"""Generates KoreanTalk.xcodeproj/project.pbxproj from the source tree."""

import os
import hashlib
import uuid

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC_DIR = ROOT  # sources are directly inside ROOT

def uid(name: str) -> str:
    """Deterministic 24-char uppercase hex UUID from a name string."""
    h = hashlib.md5(name.encode()).hexdigest().upper()
    return h[:24]

# ── Collect source files ──────────────────────────────────────────────────────

EXCLUDE_DIRS  = {".git", "KoreanTalk.xcodeproj", "__pycache__"}
EXCLUDE_FILES = {"generate_xcodeproj.py", "Info.plist"}

swift_files = []   # list of (relative_path_from_ROOT, abs_path)
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS]
    for f in filenames:
        if f.endswith(".swift") and f not in EXCLUDE_FILES:
            abs_path = os.path.join(dirpath, f)
            rel_path = os.path.relpath(abs_path, ROOT)
            swift_files.append((rel_path, abs_path))

swift_files.sort()

# ── UUIDs ─────────────────────────────────────────────────────────────────────

PROJECT_UUID       = uid("PROJECT")
MAIN_GROUP_UUID    = uid("MAIN_GROUP")
SRC_GROUP_UUID     = uid("SRC_GROUP")
PRODUCTS_GROUP_UUID = uid("PRODUCTS_GROUP")
TARGET_UUID        = uid("TARGET")
APP_PRODUCT_UUID   = uid("APP_PRODUCT")
SOURCES_PHASE_UUID = uid("SOURCES_PHASE")
FRAMEWORKS_PHASE_UUID = uid("FRAMEWORKS_PHASE")
RESOURCES_PHASE_UUID = uid("RESOURCES_PHASE")
DEBUG_CONFIG_UUID  = uid("DEBUG_CONFIG")
RELEASE_CONFIG_UUID= uid("RELEASE_CONFIG")
TARGET_DEBUG_UUID  = uid("TARGET_DEBUG")
TARGET_RELEASE_UUID= uid("TARGET_RELEASE")
CONFIG_LIST_UUID   = uid("CONFIG_LIST")
TARGET_CONFIG_LIST_UUID = uid("TARGET_CONFIG_LIST")
INFOPLIST_REF_UUID = uid("INFOPLIST_REF")

# Speech.framework
SPEECH_FW_REF  = uid("SPEECH_FW_REF")
SPEECH_FW_FILE = uid("SPEECH_FW_FILE")
# AVFoundation.framework
AVF_FW_REF  = uid("AVF_FW_REF")
AVF_FW_FILE = uid("AVF_FW_FILE")

# Per-file UUIDs
file_ref_uids  = {rel: uid("FILE_REF_"+rel)  for rel,_ in swift_files}
build_file_uids = {rel: uid("BUILD_FILE_"+rel) for rel,_ in swift_files}

# Group UUIDs per directory
all_dirs = set()
for rel, _ in swift_files:
    parts = rel.split(os.sep)[:-1]
    for i in range(len(parts)):
        all_dirs.add(os.sep.join(parts[:i+1]))
group_uids = {d: uid("GROUP_"+d) for d in all_dirs}

# ── Helpers ───────────────────────────────────────────────────────────────────

def q(s):
    return s  # unquoted strings in old-style plist

def sect(title, body):
    return f"\n/* Begin {title} section */\n{body}\n/* End {title} section */"

# ── PBXBuildFile ──────────────────────────────────────────────────────────────

build_file_entries = ""
for rel, _ in swift_files:
    buid = build_file_uids[rel]
    fuid = file_ref_uids[rel]
    name = os.path.basename(rel)
    build_file_entries += f"\t\t{buid} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fuid} /* {name} */; }};\n"

# Framework build files
build_file_entries += f"\t\t{SPEECH_FW_FILE} /* Speech.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {SPEECH_FW_REF} /* Speech.framework */; }};\n"
build_file_entries += f"\t\t{AVF_FW_FILE} /* AVFoundation.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {AVF_FW_REF} /* AVFoundation.framework */; }};\n"

# ── PBXFileReference ──────────────────────────────────────────────────────────

file_ref_entries = ""
for rel, _ in swift_files:
    fuid = file_ref_uids[rel]
    name = os.path.basename(rel)
    file_ref_entries += f'\t\t{fuid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};\n'

file_ref_entries += f'\t\t{APP_PRODUCT_UUID} /* KoreanTalk.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = KoreanTalk.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n'
file_ref_entries += f'\t\t{INFOPLIST_REF_UUID} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};\n'
file_ref_entries += f'\t\t{SPEECH_FW_REF} /* Speech.framework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = Speech.framework; path = System/Library/Frameworks/Speech.framework; sourceTree = SDKROOT; }};\n'
file_ref_entries += f'\t\t{AVF_FW_REF} /* AVFoundation.framework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = AVFoundation.framework; path = System/Library/Frameworks/AVFoundation.framework; sourceTree = SDKROOT; }};\n'

# ── PBXFrameworksBuildPhase ───────────────────────────────────────────────────

frameworks_phase = f"""\t\t{FRAMEWORKS_PHASE_UUID} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{SPEECH_FW_FILE} /* Speech.framework in Frameworks */,
\t\t\t\t{AVF_FW_FILE} /* AVFoundation.framework in Frameworks */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};\n"""

# ── PBXGroup ──────────────────────────────────────────────────────────────────

def files_in_dir(target_dir):
    """Return (rel, name) for swift files directly inside target_dir."""
    results = []
    for rel, _ in swift_files:
        parts = rel.split(os.sep)
        file_dir = os.sep.join(parts[:-1]) if len(parts) > 1 else ""
        if file_dir == target_dir:
            results.append((rel, parts[-1]))
    return results

def subdirs_of(target_dir):
    """Return immediate subdirectories of target_dir."""
    results = []
    for d in sorted(all_dirs):
        parts = d.split(os.sep)
        parent = os.sep.join(parts[:-1])
        if parent == target_dir:
            results.append(d)
    return results

def build_group_children(dir_path):
    children = []
    for subdir in subdirs_of(dir_path):
        subdir_name = subdir.split(os.sep)[-1]
        children.append(f"\t\t\t\t{group_uids[subdir]} /* {subdir_name} */,\n")
    for rel, name in files_in_dir(dir_path):
        children.append(f"\t\t\t\t{file_ref_uids[rel]} /* {name} */,\n")
    return "".join(children)

group_entries = ""

# Main group
main_children = f"\t\t\t\t{SRC_GROUP_UUID} /* KoreanTalk */,\n\t\t\t\t{PRODUCTS_GROUP_UUID} /* Products */,\n"
group_entries += f"""\t\t{MAIN_GROUP_UUID} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{main_children}\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};\n"""

# Products group
group_entries += f"""\t\t{PRODUCTS_GROUP_UUID} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{APP_PRODUCT_UUID} /* KoreanTalk.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};\n"""

# Root source group (top-level swift files + Info.plist + subdirs)
root_children = build_group_children("")
root_children += f"\t\t\t\t{INFOPLIST_REF_UUID} /* Info.plist */,\n"
group_entries += f"""\t\t{SRC_GROUP_UUID} /* KoreanTalk */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{root_children}\t\t\t);
\t\t\tpath = KoreanTalk;
\t\t\tsourceTree = "<group>";
\t\t}};\n"""

# Sub-groups (Models, Services, ViewModels, Views, Views/Conversation, etc.)
for d in sorted(all_dirs):
    parts = d.split(os.sep)
    name = parts[-1]
    children = build_group_children(d)
    group_entries += f"""\t\t{group_uids[d]} /* {name} */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{children}\t\t\t);
\t\t\tpath = {name};
\t\t\tsourceTree = "<group>";
\t\t}};\n"""

# ── PBXNativeTarget ───────────────────────────────────────────────────────────

native_target = f"""\t\t{TARGET_UUID} /* KoreanTalk */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {TARGET_CONFIG_LIST_UUID} /* Build configuration list for PBXNativeTarget "KoreanTalk" */;
\t\t\tbuildPhases = (
\t\t\t\t{SOURCES_PHASE_UUID} /* Sources */,
\t\t\t\t{FRAMEWORKS_PHASE_UUID} /* Frameworks */,
\t\t\t\t{RESOURCES_PHASE_UUID} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = KoreanTalk;
\t\t\tproductName = KoreanTalk;
\t\t\tproductReference = {APP_PRODUCT_UUID} /* KoreanTalk.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};\n"""

# ── PBXProject ────────────────────────────────────────────────────────────────

project_obj = f"""\t\t{PROJECT_UUID} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1620;
\t\t\t\tLastUpgradeCheck = 1620;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{TARGET_UUID} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 16.2;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {CONFIG_LIST_UUID} /* Build configuration list for PBXProject "KoreanTalk" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {MAIN_GROUP_UUID};
\t\t\tproductRefGroup = {PRODUCTS_GROUP_UUID} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{TARGET_UUID} /* KoreanTalk */,
\t\t\t);
\t\t}};\n"""

# ── PBXResourcesBuildPhase ────────────────────────────────────────────────────

resources_phase = f"""\t\t{RESOURCES_PHASE_UUID} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};\n"""

# ── PBXSourcesBuildPhase ──────────────────────────────────────────────────────

source_file_lines = ""
for rel, _ in swift_files:
    name = os.path.basename(rel)
    source_file_lines += f"\t\t\t\t{build_file_uids[rel]} /* {name} in Sources */,\n"

sources_phase = f"""\t\t{SOURCES_PHASE_UUID} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{source_file_lines}\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};\n"""

# ── XCBuildConfiguration ──────────────────────────────────────────────────────

COMMON_SETTINGS = """
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tASSET_CATALOG_APP_ICON_SET = AppIcon;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_ENABLE_OBJC_WEAK = YES;
\t\t\t\tCLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_COMMA = YES;
\t\t\t\tCLANG_WARN_CONSTANT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
\t\t\t\tCLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;
\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;
\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;
\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;
\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
\t\t\t\tCLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
\t\t\t\tCLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
\t\t\t\tCLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
\t\t\t\tCLANG_WARN_STRICT_PROTOTYPES = YES;
\t\t\t\tCLANG_WARN_SUSPICIOUS_MOVE = YES;
\t\t\t\tCLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;
\t\t\t\tCLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = ("DEBUG=1", "$(inherited)");
\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;
\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
"""

debug_config = f"""\t\t{DEBUG_CONFIG_UUID} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{{COMMON_SETTINGS}\t\t\t}};
\t\t\tname = Debug;
\t\t}};\n"""

release_config = f"""\t\t{RELEASE_CONFIG_UUID} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t}};
\t\t\tname = Release;
\t\t}};\n"""

TARGET_SETTINGS = f"""
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = KoreanTalk/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks");
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "com.koreantalk.app";
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 1;
"""

target_debug = f"""\t\t{TARGET_DEBUG_UUID} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{{TARGET_SETTINGS}\t\t\t}};
\t\t\tname = Debug;
\t\t}};\n"""

target_release = f"""\t\t{TARGET_RELEASE_UUID} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{{TARGET_SETTINGS}\t\t\t}};
\t\t\tname = Release;
\t\t}};\n"""

# ── XCConfigurationList ───────────────────────────────────────────────────────

config_list = f"""\t\t{CONFIG_LIST_UUID} /* Build configuration list for PBXProject "KoreanTalk" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{DEBUG_CONFIG_UUID} /* Debug */,
\t\t\t\t{RELEASE_CONFIG_UUID} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};\n"""

target_config_list = f"""\t\t{TARGET_CONFIG_LIST_UUID} /* Build configuration list for PBXNativeTarget "KoreanTalk" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{TARGET_DEBUG_UUID} /* Debug */,
\t\t\t\t{TARGET_RELEASE_UUID} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};\n"""

# ── Assemble project.pbxproj ──────────────────────────────────────────────────

pbxproj = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{
{sect("PBXBuildFile", build_file_entries)}
{sect("PBXFileReference", file_ref_entries)}
{sect("PBXFrameworksBuildPhase", frameworks_phase)}
{sect("PBXGroup", group_entries)}
{sect("PBXNativeTarget", native_target)}
{sect("PBXProject", project_obj)}
{sect("PBXResourcesBuildPhase", resources_phase)}
{sect("PBXSourcesBuildPhase", sources_phase)}
{sect("XCBuildConfiguration", debug_config + release_config + target_debug + target_release)}
{sect("XCConfigurationList", config_list + target_config_list)}
\t}};
\trootObject = {PROJECT_UUID} /* Project object */;
}}
"""

# ── Write files ───────────────────────────────────────────────────────────────

xcodeproj_dir = os.path.join(ROOT, "KoreanTalk.xcodeproj")
os.makedirs(xcodeproj_dir, exist_ok=True)

workspace_dir = os.path.join(xcodeproj_dir, "project.xcworkspace")
os.makedirs(workspace_dir, exist_ok=True)

pbxproj_path = os.path.join(xcodeproj_dir, "project.pbxproj")
with open(pbxproj_path, "w") as f:
    f.write(pbxproj)

workspace_data = """<?xml version="1.0" encoding="UTF-8"?>
<Workspace version = "1.0">
   <FileRef location = "self:">
   </FileRef>
</Workspace>
"""
with open(os.path.join(workspace_dir, "contents.xcworkspacedata"), "w") as f:
    f.write(workspace_data)

print(f"Generated: {pbxproj_path}")
print(f"Swift files included: {len(swift_files)}")
for rel, _ in swift_files:
    print(f"  {rel}")
