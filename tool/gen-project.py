#!/usr/bin/env python3
"""Writes DuoAssess.xcodeproj/project.pbxproj.

The Swift sources live in a *file-system synchronized* group (Xcode 16+), so
adding/removing .swift files under DuoAssess/ needs NO project regeneration.
Only rerun this if you change build settings or bundle a new folder.
Unit tests live in DuoAssessTests/ (also synchronized) and run with:
    xcodebuild test -project DuoAssess.xcodeproj -scheme DuoAssess \
      -destination 'platform=iOS Simulator,name=iPhone Duo' -derivedDataPath build/DerivedData

    python3 tool/gen-project.py    # from the project root

The `../design` folder (videos) is bundled as a folder reference -> shows up in the app
bundle as `design/`.
"""
import hashlib, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = "DuoAssess"
BUNDLE_ID = "com.duohack.duoassess"

def uid(seed): return hashlib.sha256(seed.encode()).hexdigest()[:24].upper()
ID = {k: uid("duoassess:" + k) for k in [
    "project", "mainGroup", "syncGroup", "productsGroup", "target", "appRef",
    "sources", "frameworks", "resources", "projCL", "targetCL",
    "projDebug", "projRelease", "targetDebug", "targetRelease",
    "designRef", "designBuild",
    "testTarget", "testSyncGroup", "testRef", "testSources", "testFrameworks",
    "testCL", "testDebug", "testRelease", "testDep", "testProxy"]}

def cfg(cid, name, lines):
    body = "\n".join("\t\t\t\t" + l for l in lines)
    return (f"\t\t{cid} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n"
            f"\t\t\tbuildSettings = {{\n{body}\n\t\t\t}};\n\t\t\tname = {name};\n\t\t}};")

COMMON = [
    "ALWAYS_SEARCH_USER_PATHS = NO;", "CLANG_ENABLE_OBJC_ARC = YES;",
    "CLANG_ENABLE_MODULES = YES;", "COPY_PHASE_STRIP = NO;",
    'DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";', "ENABLE_STRICT_OBJC_MSGSEND = YES;",
    "GCC_C_LANGUAGE_STANDARD = gnu17;", "MTL_FAST_MATH = YES;", "SDKROOT = iphoneos;",
    "SWIFT_VERSION = 5.0;", "IPHONEOS_DEPLOYMENT_TARGET = 27.1;",
    "ENABLE_USER_SCRIPT_SANDBOXING = YES;",
]
PROJ_DEBUG = COMMON + ["ENABLE_TESTABILITY = YES;", "GCC_OPTIMIZATION_LEVEL = 0;",
    'GCC_PREPROCESSOR_DEFINITIONS = ("DEBUG=1", "$(inherited)");', "ONLY_ACTIVE_ARCH = YES;",
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";', 'SWIFT_OPTIMIZATION_LEVEL = "-Onone";']
PROJ_RELEASE = COMMON + ["ENABLE_NS_ASSERTIONS = NO;", "GCC_OPTIMIZATION_LEVEL = s;",
    "SWIFT_COMPILATION_MODE = wholemodule;", "VALIDATE_PRODUCT = YES;"]
TARGET = [
    "CODE_SIGN_STYLE = Automatic;", "CURRENT_PROJECT_VERSION = 1;", "MARKETING_VERSION = 0.1.0;",
    "GENERATE_INFOPLIST_FILE = YES;",
    'INFOPLIST_KEY_CFBundleDisplayName = "Duo Assess";',
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;",
    "INFOPLIST_KEY_UILaunchScreen_Generation = YES;",
    'INFOPLIST_KEY_UISupportedInterfaceOrientations = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";',
    'LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks");',
    f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};", 'PRODUCT_NAME = "$(TARGET_NAME)";',
    "SWIFT_EMIT_LOC_STRINGS = YES;", "SUPPORTS_MACCATALYST = NO;", "TARGETED_DEVICE_FAMILY = 1;",
    "SWIFT_STRICT_CONCURRENCY = minimal;",
]

TEST_SETTINGS = [
    "CODE_SIGN_STYLE = Automatic;", "CURRENT_PROJECT_VERSION = 1;", "MARKETING_VERSION = 0.1.0;",
    "GENERATE_INFOPLIST_FILE = YES;",
    'BUNDLE_LOADER = "$(TEST_HOST)";',
    f'TEST_HOST = "$(BUILT_PRODUCTS_DIR)/{NAME}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/{NAME}";',
    'LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks");',
    f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID}.tests;", 'PRODUCT_NAME = "$(TARGET_NAME)";',
    "SWIFT_EMIT_LOC_STRINGS = NO;", "TARGETED_DEVICE_FAMILY = 1;",
    "SWIFT_STRICT_CONCURRENCY = minimal;",
]

L = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};",
     "\tobjectVersion = 77;", "\tobjects = {", ""]
L += ["/* Begin PBXBuildFile section */",
      f"\t\t{ID['designBuild']} /* design in Resources */ = {{isa = PBXBuildFile; fileRef = {ID['designRef']} /* design */; }};",
      "/* End PBXBuildFile section */", ""]
L += ["/* Begin PBXFileReference section */",
      f"\t\t{ID['appRef']} /* {NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};",
      f"\t\t{ID['designRef']} /* design */ = {{isa = PBXFileReference; lastKnownFileType = folder; name = design; path = design; sourceTree = \"<group>\"; }};",
      f"\t\t{ID['testRef']} /* {NAME}Tests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = {NAME}Tests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};",
      "/* End PBXFileReference section */", ""]
L += ["/* Begin PBXContainerItemProxy section */",
      f"\t\t{ID['testProxy']} /* PBXContainerItemProxy */ = {{isa = PBXContainerItemProxy; containerPortal = {ID['project']}; proxyType = 1; remoteGlobalIDString = {ID['target']}; remoteInfo = {NAME}; }};",
      "/* End PBXContainerItemProxy section */", ""]
L += ["/* Begin PBXFileSystemSynchronizedRootGroup section */",
      f"\t\t{ID['syncGroup']} /* {NAME} */ = {{isa = PBXFileSystemSynchronizedRootGroup; explicitFileTypes = {{}}; explicitFolders = (); path = {NAME}; sourceTree = \"<group>\"; }};",
      f"\t\t{ID['testSyncGroup']} /* {NAME}Tests */ = {{isa = PBXFileSystemSynchronizedRootGroup; explicitFileTypes = {{}}; explicitFolders = (); path = {NAME}Tests; sourceTree = \"<group>\"; }};",
      "/* End PBXFileSystemSynchronizedRootGroup section */", ""]
L += ["/* Begin PBXFrameworksBuildPhase section */",
      f"\t\t{ID['frameworks']} /* Frameworks */ = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};",
      f"\t\t{ID['testFrameworks']} /* Frameworks */ = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};",
      "/* End PBXFrameworksBuildPhase section */", ""]
L += ["/* Begin PBXGroup section */",
      f"\t\t{ID['mainGroup']} = {{isa = PBXGroup; children = ({ID['syncGroup']} /* {NAME} */, {ID['testSyncGroup']} /* {NAME}Tests */, {ID['designRef']} /* design */, {ID['productsGroup']} /* Products */); sourceTree = \"<group>\"; }};",
      f"\t\t{ID['productsGroup']} /* Products */ = {{isa = PBXGroup; children = ({ID['appRef']} /* {NAME}.app */, {ID['testRef']} /* {NAME}Tests.xctest */); name = Products; sourceTree = \"<group>\"; }};",
      "/* End PBXGroup section */", ""]
L += ["/* Begin PBXNativeTarget section */",
      f"\t\t{ID['target']} /* {NAME} */ = {{", "\t\t\tisa = PBXNativeTarget;",
      f"\t\t\tbuildConfigurationList = {ID['targetCL']};",
      f"\t\t\tbuildPhases = ({ID['sources']} /* Sources */, {ID['frameworks']} /* Frameworks */, {ID['resources']} /* Resources */);",
      "\t\t\tbuildRules = ();", "\t\t\tdependencies = ();",
      f"\t\t\tfileSystemSynchronizedGroups = ({ID['syncGroup']} /* {NAME} */);",
      f"\t\t\tname = {NAME};", f"\t\t\tproductName = {NAME};",
      f"\t\t\tproductReference = {ID['appRef']} /* {NAME}.app */;",
      "\t\t\tproductType = \"com.apple.product-type.application\";", "\t\t};",
      f"\t\t{ID['testTarget']} /* {NAME}Tests */ = {{", "\t\t\tisa = PBXNativeTarget;",
      f"\t\t\tbuildConfigurationList = {ID['testCL']};",
      f"\t\t\tbuildPhases = ({ID['testSources']} /* Sources */, {ID['testFrameworks']} /* Frameworks */);",
      "\t\t\tbuildRules = ();", f"\t\t\tdependencies = ({ID['testDep']} /* PBXTargetDependency */);",
      f"\t\t\tfileSystemSynchronizedGroups = ({ID['testSyncGroup']} /* {NAME}Tests */);",
      f"\t\t\tname = {NAME}Tests;", f"\t\t\tproductName = {NAME}Tests;",
      f"\t\t\tproductReference = {ID['testRef']} /* {NAME}Tests.xctest */;",
      "\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";", "\t\t};",
      "/* End PBXNativeTarget section */", ""]
L += ["/* Begin PBXProject section */",
      f"\t\t{ID['project']} /* Project object */ = {{", "\t\t\tisa = PBXProject;",
      "\t\t\tattributes = {BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 2710; LastUpgradeCheck = 2710; TargetAttributes = {" + ID['testTarget'] + " = {TestTargetID = " + ID['target'] + "; }; }; };",
      f"\t\t\tbuildConfigurationList = {ID['projCL']};",
      "\t\t\tdevelopmentRegion = en;", "\t\t\thasScannedForEncodings = 0;",
      "\t\t\tknownRegions = (en, Base);", f"\t\t\tmainGroup = {ID['mainGroup']};",
      "\t\t\tpreferredProjectObjectVersion = 77;",
      f"\t\t\tproductRefGroup = {ID['productsGroup']} /* Products */;",
      "\t\t\tprojectDirPath = \"\";", "\t\t\tprojectRoot = \"\";",
      f"\t\t\ttargets = ({ID['target']} /* {NAME} */, {ID['testTarget']} /* {NAME}Tests */);", "\t\t};",
      "/* End PBXProject section */", ""]
L += ["/* Begin PBXResourcesBuildPhase section */",
      f"\t\t{ID['resources']} /* Resources */ = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({ID['designBuild']} /* design in Resources */); runOnlyForDeploymentPostprocessing = 0; }};",
      "/* End PBXResourcesBuildPhase section */", ""]
L += ["/* Begin PBXSourcesBuildPhase section */",
      f"\t\t{ID['sources']} /* Sources */ = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};",
      f"\t\t{ID['testSources']} /* Sources */ = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};",
      "/* End PBXSourcesBuildPhase section */", ""]
L += ["/* Begin PBXTargetDependency section */",
      f"\t\t{ID['testDep']} /* PBXTargetDependency */ = {{isa = PBXTargetDependency; target = {ID['target']} /* {NAME} */; targetProxy = {ID['testProxy']} /* PBXContainerItemProxy */; }};",
      "/* End PBXTargetDependency section */", ""]
L += ["/* Begin XCBuildConfiguration section */",
      cfg(ID['projDebug'], "Debug", PROJ_DEBUG), cfg(ID['projRelease'], "Release", PROJ_RELEASE),
      cfg(ID['targetDebug'], "Debug", TARGET), cfg(ID['targetRelease'], "Release", TARGET),
      cfg(ID['testDebug'], "Debug", TEST_SETTINGS), cfg(ID['testRelease'], "Release", TEST_SETTINGS),
      "/* End XCBuildConfiguration section */", ""]
L += ["/* Begin XCConfigurationList section */",
      f"\t\t{ID['projCL']} = {{isa = XCConfigurationList; buildConfigurations = ({ID['projDebug']} /* Debug */, {ID['projRelease']} /* Release */); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};",
      f"\t\t{ID['targetCL']} = {{isa = XCConfigurationList; buildConfigurations = ({ID['targetDebug']} /* Debug */, {ID['targetRelease']} /* Release */); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};",
      f"\t\t{ID['testCL']} = {{isa = XCConfigurationList; buildConfigurations = ({ID['testDebug']} /* Debug */, {ID['testRelease']} /* Release */); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};",
      "/* End XCConfigurationList section */"]
L += ["\t};", f"\trootObject = {ID['project']} /* Project object */;", "}"]

proj = os.path.join(ROOT, f"{NAME}.xcodeproj")
os.makedirs(os.path.join(proj, "project.xcworkspace"), exist_ok=True)
os.makedirs(os.path.join(proj, "xcshareddata", "xcschemes"), exist_ok=True)
with open(os.path.join(proj, "project.pbxproj"), "w") as f:
    f.write("\n".join(L) + "\n")
with open(os.path.join(proj, "project.xcworkspace", "contents.xcworkspacedata"), "w") as f:
    f.write('<?xml version="1.0" encoding="UTF-8"?>\n<workspace version = "1.0">\n   <fileRef location = "self:">\n   </fileRef>\n</workspace>\n')
with open(os.path.join(proj, "xcshareddata", "xcschemes", f"{NAME}.xcscheme"), "w") as f:
    f.write(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2710" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{ID['target']}" BuildableName = "{NAME}.app" BlueprintName = "{NAME}" ReferencedContainer = "container:{NAME}.xcodeproj"/>
         </BuildActionEntry>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "NO" buildForProfiling = "NO" buildForArchiving = "NO" buildForAnalyzing = "NO">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{ID['testTarget']}" BuildableName = "{NAME}Tests.xctest" BlueprintName = "{NAME}Tests" ReferencedContainer = "container:{NAME}.xcodeproj"/>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{ID['testTarget']}" BuildableName = "{NAME}Tests.xctest" BlueprintName = "{NAME}Tests" ReferencedContainer = "container:{NAME}.xcodeproj"/>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{ID['target']}" BuildableName = "{NAME}.app" BlueprintName = "{NAME}" ReferencedContainer = "container:{NAME}.xcodeproj"/>
      </BuildableProductRunnable>
   </LaunchAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"/>
</Scheme>
''')
print("wrote", proj)
