import pathlib

p = pathlib.Path(__file__).resolve().parent.parent / "NOCOAI.xcodeproj" / "project.pbxproj"
text = p.read_text(encoding="utf-8")

if "WCH0000030000000000000001" in text:
    print("already patched")
    raise SystemExit(0)

build_files = """
\t\tWCH0000010000000000000001 /* WatchBridgeModels.swift in Sources */ = {isa = PBXBuildFile; fileRef = WCH000002000000000000000E /* WatchBridgeModels.swift */; };
\t\tWCH0000010000000000000002 /* WatchConnectivityBridge.swift in Sources */ = {isa = PBXBuildFile; fileRef = WCH0000020000000000000010 /* WatchConnectivityBridge.swift */; };
\t\tWCH0000010000000000000003 /* NOCOWatchApp.swift in Sources */ = {isa = PBXBuildFile; fileRef = WCH0000020000000000000001 /* NOCOWatchApp.swift */; };
\t\tWCH0000010000000000000004 /* WatchRootView.swift in Sources */ = {isa = PBXBuildFile; fileRef = WCH0000020000000000000002 /* WatchRootView.swift */; };
\t\tWCH0000010000000000000005 /* WatchAskView.swift in Sources */ = {isa = PBXBuildFile; fileRef = WCH0000020000000000000003 /* WatchAskView.swift */; };
\t\tWCH0000010000000000000006 /* WatchVoiceView.swift in Sources */ = {isa = PBXBuildFile; fileRef = WCH0000020000000000000004 /* WatchVoiceView.swift */; };
\t\tWCH0000010000000000000007 /* WatchLastAnswerView.swift in Sources */ = {isa = PBXBuildFile; fileRef = WCH0000020000000000000005 /* WatchLastAnswerView.swift */; };
\t\tWCH0000010000000000000008 /* WatchStatusView.swift in Sources */ = {isa = PBXBuildFile; fileRef = WCH0000020000000000000006 /* WatchStatusView.swift */; };
\t\tWCH0000010000000000000009 /* WatchRainbowGlow.swift in Sources */ = {isa = PBXBuildFile; fileRef = WCH0000020000000000000007 /* WatchRainbowGlow.swift */; };
\t\tWCH000001000000000000000A /* WatchVoiceEngine.swift in Sources */ = {isa = PBXBuildFile; fileRef = WCH0000020000000000000008 /* WatchVoiceEngine.swift */; };
\t\tWCH000001000000000000000B /* WatchSessionClient.swift in Sources */ = {isa = PBXBuildFile; fileRef = WCH0000020000000000000009 /* WatchSessionClient.swift */; };
\t\tWCH000001000000000000000C /* WatchHaptics.swift in Sources */ = {isa = PBXBuildFile; fileRef = WCH000002000000000000000A /* WatchHaptics.swift */; };
\t\tWCH000001000000000000000D /* WatchController.swift in Sources */ = {isa = PBXBuildFile; fileRef = WCH000002000000000000000B /* WatchController.swift */; };
\t\tWCH000001000000000000000E /* WatchAppIntents.swift in Sources */ = {isa = PBXBuildFile; fileRef = WCH000002000000000000000C /* WatchAppIntents.swift */; };
\t\tWCH000001000000000000000F /* NOCOComplication.swift in Sources */ = {isa = PBXBuildFile; fileRef = WCH000002000000000000000D /* NOCOComplication.swift */; };
\t\tWCH0000010000000000000010 /* WatchBridgeModels.swift in Sources */ = {isa = PBXBuildFile; fileRef = WCH000002000000000000000E /* WatchBridgeModels.swift */; };
\t\tWCH0000010000000000000011 /* NOCOWatch.app in Embed Watch Content */ = {isa = PBXBuildFile; fileRef = WCH0000030000000000000001 /* NOCOWatch.app */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
"""

file_refs = """
\t\tWCH0000020000000000000001 /* NOCOWatchApp.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = NOCOWatchApp.swift; sourceTree = "<group>"; };
\t\tWCH0000020000000000000002 /* WatchRootView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WatchRootView.swift; sourceTree = "<group>"; };
\t\tWCH0000020000000000000003 /* WatchAskView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WatchAskView.swift; sourceTree = "<group>"; };
\t\tWCH0000020000000000000004 /* WatchVoiceView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WatchVoiceView.swift; sourceTree = "<group>"; };
\t\tWCH0000020000000000000005 /* WatchLastAnswerView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WatchLastAnswerView.swift; sourceTree = "<group>"; };
\t\tWCH0000020000000000000006 /* WatchStatusView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WatchStatusView.swift; sourceTree = "<group>"; };
\t\tWCH0000020000000000000007 /* WatchRainbowGlow.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WatchRainbowGlow.swift; sourceTree = "<group>"; };
\t\tWCH0000020000000000000008 /* WatchVoiceEngine.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WatchVoiceEngine.swift; sourceTree = "<group>"; };
\t\tWCH0000020000000000000009 /* WatchSessionClient.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WatchSessionClient.swift; sourceTree = "<group>"; };
\t\tWCH000002000000000000000A /* WatchHaptics.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WatchHaptics.swift; sourceTree = "<group>"; };
\t\tWCH000002000000000000000B /* WatchController.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WatchController.swift; sourceTree = "<group>"; };
\t\tWCH000002000000000000000C /* WatchAppIntents.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WatchAppIntents.swift; sourceTree = "<group>"; };
\t\tWCH000002000000000000000D /* NOCOComplication.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = NOCOComplication.swift; sourceTree = "<group>"; };
\t\tWCH000002000000000000000E /* WatchBridgeModels.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WatchBridgeModels.swift; sourceTree = "<group>"; };
\t\tWCH0000020000000000000010 /* WatchConnectivityBridge.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WatchConnectivityBridge.swift; sourceTree = "<group>"; };
\t\tWCH00000200000000000000PL /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
\t\tWCH00000200000000000000EN /* NOCOWatch.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = NOCOWatch.entitlements; sourceTree = "<group>"; };
\t\tWCH0000030000000000000001 /* NOCOWatch.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = NOCOWatch.app; sourceTree = BUILT_PRODUCTS_DIR; };
"""

text = text.replace("/* End PBXBuildFile section */", build_files + "/* End PBXBuildFile section */")
text = text.replace("/* End PBXFileReference section */", file_refs + "/* End PBXFileReference section */")

text = text.replace(
    "\t\t\t\tBC0000050000000000000001 /* NOCOAIBroadcast */,\n\t\t\t\tWDG0000050000000000000002 /* Shared */,",
    "\t\t\t\tBC0000050000000000000001 /* NOCOAIBroadcast */,\n\t\t\t\tWCH0000050000000000000001 /* NOCOWatch */,\n\t\t\t\tWDG0000050000000000000002 /* Shared */,",
)

text = text.replace(
    "\t\t\t\tBC0000030000000000000001 /* NOCOAIBroadcast.appex */,\n\t\t\t);",
    "\t\t\t\tBC0000030000000000000001 /* NOCOAIBroadcast.appex */,\n\t\t\t\tWCH0000030000000000000001 /* NOCOWatch.app */,\n\t\t\t);",
)

watch_group = """
\t\tWCH0000050000000000000001 /* NOCOWatch */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\tWCH0000050000000000000002 /* App */,
\t\t\t\tWCH0000050000000000000003 /* Views */,
\t\t\t\tWCH0000050000000000000004 /* Animations */,
\t\t\t\tWCH0000050000000000000005 /* Voice */,
\t\t\t\tWCH0000050000000000000006 /* Connectivity */,
\t\t\t\tWCH0000050000000000000007 /* Haptics */,
\t\t\t\tWCH0000050000000000000008 /* Models */,
\t\t\t\tWCH0000050000000000000009 /* AppIntents */,
\t\t\t\tWCH000005000000000000000A /* Complication */,
\t\t\t\tWCH00000200000000000000PL /* Info.plist */,
\t\t\t\tWCH00000200000000000000EN /* NOCOWatch.entitlements */,
\t\t\t);
\t\t\tpath = NOCOWatch;
\t\t\tsourceTree = "<group>";
\t\t};
\t\tWCH0000050000000000000002 /* App */ = {isa = PBXGroup; children = (WCH0000020000000000000001 /* NOCOWatchApp.swift */); path = App; sourceTree = "<group>"; };
\t\tWCH0000050000000000000003 /* Views */ = {isa = PBXGroup; children = (WCH0000020000000000000002 /* WatchRootView.swift */, WCH0000020000000000000003 /* WatchAskView.swift */, WCH0000020000000000000004 /* WatchVoiceView.swift */, WCH0000020000000000000005 /* WatchLastAnswerView.swift */, WCH0000020000000000000006 /* WatchStatusView.swift */); path = Views; sourceTree = "<group>"; };
\t\tWCH0000050000000000000004 /* Animations */ = {isa = PBXGroup; children = (WCH0000020000000000000007 /* WatchRainbowGlow.swift */); path = Animations; sourceTree = "<group>"; };
\t\tWCH0000050000000000000005 /* Voice */ = {isa = PBXGroup; children = (WCH0000020000000000000008 /* WatchVoiceEngine.swift */); path = Voice; sourceTree = "<group>"; };
\t\tWCH0000050000000000000006 /* Connectivity */ = {isa = PBXGroup; children = (WCH0000020000000000000009 /* WatchSessionClient.swift */); path = Connectivity; sourceTree = "<group>"; };
\t\tWCH0000050000000000000007 /* Haptics */ = {isa = PBXGroup; children = (WCH000002000000000000000A /* WatchHaptics.swift */); path = Haptics; sourceTree = "<group>"; };
\t\tWCH0000050000000000000008 /* Models */ = {isa = PBXGroup; children = (WCH000002000000000000000B /* WatchController.swift */); path = Models; sourceTree = "<group>"; };
\t\tWCH0000050000000000000009 /* AppIntents */ = {isa = PBXGroup; children = (WCH000002000000000000000C /* WatchAppIntents.swift */); path = AppIntents; sourceTree = "<group>"; };
\t\tWCH000005000000000000000A /* Complication */ = {isa = PBXGroup; children = (WCH000002000000000000000D /* NOCOComplication.swift */); path = Complication; sourceTree = "<group>"; };
"""
text = text.replace("/* End PBXGroup section */", watch_group + "/* End PBXGroup section */")

text = text.replace(
    "\t\t\t\tKBD0000020000000000000013 /* KeyboardChipPreferences.swift */,\n\t\t\t);",
    "\t\t\t\tKBD0000020000000000000013 /* KeyboardChipPreferences.swift */,\n\t\t\t\tWCH000002000000000000000E /* WatchBridgeModels.swift */,\n\t\t\t);",
)

text = text.replace(
    "\t\t\t\tNA00000200000000000000V3 /* VisionLiveSessionController.swift */,\n\t\t\t);",
    "\t\t\t\tNA00000200000000000000V3 /* VisionLiveSessionController.swift */,\n\t\t\t\tWCH0000020000000000000010 /* WatchConnectivityBridge.swift */,\n\t\t\t);",
)

text = text.replace(
    "\t\t\t\tNA0000010000000000000015 /* LocalNetworkService.swift in Sources */,\n\t\t\t);",
    "\t\t\t\tNA0000010000000000000015 /* LocalNetworkService.swift in Sources */,\n\t\t\t\tWCH0000010000000000000001 /* WatchBridgeModels.swift in Sources */,\n\t\t\t\tWCH0000010000000000000002 /* WatchConnectivityBridge.swift in Sources */,\n\t\t\t);",
)

text = text.replace(
    "\t\t\t\tWDG00000E0000000000000001 /* Embed Foundation Extensions */,",
    "\t\t\t\tWCH00000E0000000000000001 /* Embed Watch Content */,\n\t\t\t\tWDG00000E0000000000000001 /* Embed Foundation Extensions */,",
)

text = text.replace(
    "\t\t\tdependencies = (\n\t\t\t\tWDG00000D000000000000001 /* PBXTargetDependency */,",
    "\t\t\tdependencies = (\n\t\t\t\tWCH00000D000000000000001 /* PBXTargetDependency */,\n\t\t\t\tWDG00000D000000000000001 /* PBXTargetDependency */,",
)

embed_watch = """
\t\tWCH00000E0000000000000001 /* Embed Watch Content */ = {
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "$(CONTENTS_FOLDER_PATH)/Watch";
\t\t\tdstSubfolderSpec = 16;
\t\t\tfiles = (
\t\t\t\tWCH0000010000000000000011 /* NOCOWatch.app in Embed Watch Content */,
\t\t\t);
\t\t\tname = "Embed Watch Content";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
"""
text = text.replace("/* End PBXCopyFilesBuildPhase section */", embed_watch + "/* End PBXCopyFilesBuildPhase section */")

proxy = """
\t\tWCH00000C000000000000001 /* PBXContainerItemProxy */ = {
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = NA00000A0000000000000001 /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = WCH0000060000000000000001;
\t\t\tremoteInfo = NOCOWatch;
\t\t};
"""
text = text.replace("/* End PBXContainerItemProxy section */", proxy + "/* End PBXContainerItemProxy section */")

dep = """
\t\tWCH00000D000000000000001 /* PBXTargetDependency */ = {
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = WCH0000060000000000000001 /* NOCOWatch */;
\t\t\ttargetProxy = WCH00000C000000000000001 /* PBXContainerItemProxy */;
\t\t};
"""
text = text.replace("/* End PBXTargetDependency section */", dep + "/* End PBXTargetDependency section */")

target = """
\t\tWCH0000060000000000000001 /* NOCOWatch */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = WCH0000090000000000000002 /* Build configuration list for PBXNativeTarget "NOCOWatch" */;
\t\t\tbuildPhases = (
\t\t\t\tWCH0000070000000000000001 /* Sources */,
\t\t\t\tWCH0000040000000000000001 /* Frameworks */,
\t\t\t\tWCH0000080000000000000001 /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = NOCOWatch;
\t\t\tproductName = NOCOWatch;
\t\t\tproductReference = WCH0000030000000000000001 /* NOCOWatch.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t};
"""
text = text.replace("/* End PBXNativeTarget section */", target + "/* End PBXNativeTarget section */")

text = text.replace(
    "\t\t\t\ttargets = (\n\t\t\t\tNA0000060000000000000001 /* NOCOAI */,",
    "\t\t\t\ttargets = (\n\t\t\t\tNA0000060000000000000001 /* NOCOAI */,\n\t\t\t\tWCH0000060000000000000001 /* NOCOWatch */,",
)

text = text.replace(
    "\t\t\t\t\tBC0000060000000000000001 = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;\n\t\t\t\t\t};",
    "\t\t\t\t\tBC0000060000000000000001 = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;\n\t\t\t\t\t};\n\t\t\t\t\tWCH0000060000000000000001 = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;\n\t\t\t\t\t};",
)

frameworks = """
\t\tWCH0000040000000000000001 /* Frameworks */ = {
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
"""
text = text.replace("/* End PBXFrameworksBuildPhase section */", frameworks + "/* End PBXFrameworksBuildPhase section */")

resources = """
\t\tWCH0000080000000000000001 /* Resources */ = {
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
"""
text = text.replace("/* End PBXResourcesBuildPhase section */", resources + "/* End PBXResourcesBuildPhase section */")

sources = """
\t\tWCH0000070000000000000001 /* Sources */ = {
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\tWCH0000010000000000000003 /* NOCOWatchApp.swift in Sources */,
\t\t\t\tWCH0000010000000000000004 /* WatchRootView.swift in Sources */,
\t\t\t\tWCH0000010000000000000005 /* WatchAskView.swift in Sources */,
\t\t\t\tWCH0000010000000000000006 /* WatchVoiceView.swift in Sources */,
\t\t\t\tWCH0000010000000000000007 /* WatchLastAnswerView.swift in Sources */,
\t\t\t\tWCH0000010000000000000008 /* WatchStatusView.swift in Sources */,
\t\t\t\tWCH0000010000000000000009 /* WatchRainbowGlow.swift in Sources */,
\t\t\t\tWCH000001000000000000000A /* WatchVoiceEngine.swift in Sources */,
\t\t\t\tWCH000001000000000000000B /* WatchSessionClient.swift in Sources */,
\t\t\t\tWCH000001000000000000000C /* WatchHaptics.swift in Sources */,
\t\t\t\tWCH000001000000000000000D /* WatchController.swift in Sources */,
\t\t\t\tWCH000001000000000000000E /* WatchAppIntents.swift in Sources */,
\t\t\t\tWCH000001000000000000000F /* NOCOComplication.swift in Sources */,
\t\t\t\tWCH0000010000000000000010 /* WatchBridgeModels.swift in Sources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
"""
text = text.replace("/* Begin PBXSourcesBuildPhase section */", "/* Begin PBXSourcesBuildPhase section */" + sources)

configs = """
\t\tWCH00000A0000000000000001 /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tCODE_SIGN_ENTITLEMENTS = NOCOWatch/NOCOWatch.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = NOCOWatch/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = de.noco.nocoai.watchkitapp;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = watchos;
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 4;
\t\t\t\tWATCHOS_DEPLOYMENT_TARGET = 9.0;
\t\t\t};
\t\t\tname = Debug;
\t\t};
\t\tWCH00000A0000000000000002 /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tCODE_SIGN_ENTITLEMENTS = NOCOWatch/NOCOWatch.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = NOCOWatch/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = de.noco.nocoai.watchkitapp;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = watchos;
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 4;
\t\t\t\tWATCHOS_DEPLOYMENT_TARGET = 9.0;
\t\t\t};
\t\t\tname = Release;
\t\t};
"""
text = text.replace("/* End XCBuildConfiguration section */", configs + "/* End XCBuildConfiguration section */")

config_list = """
\t\tWCH0000090000000000000002 /* Build configuration list for PBXNativeTarget "NOCOWatch" */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\tWCH00000A0000000000000001 /* Debug */,
\t\t\t\tWCH00000A0000000000000002 /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t};
"""
text = text.replace("/* End XCConfigurationList section */", config_list + "/* End XCConfigurationList section */")

p.write_text(text, encoding="utf-8")
print("pbxproj patched")
