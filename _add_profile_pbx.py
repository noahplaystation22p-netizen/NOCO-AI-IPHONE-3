from pathlib import Path

p = Path(r"C:\Users\noah_\Desktop\IOS NOCO AI X APP\github-repo-clean\NOCOAI.xcodeproj\project.pbxproj")
t = p.read_text(encoding="utf-8")
bid = "NA0000010000000000000050"
fid = "NA0000020000000000000050"
name = "UserProfileStore.swift"
if name in t:
    print("already in pbx")
else:
    t = t.replace(
        "/* Begin PBXBuildFile section */\n",
        f"/* Begin PBXBuildFile section */\n\t\t{bid} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {name} */; }};\n",
    )
    t = t.replace(
        "/* Begin PBXFileReference section */\n",
        f'/* Begin PBXFileReference section */\n\t\t{fid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};\n',
    )
    needle = "NA0000020000000000000007 /* ConnectionStore.swift */,"
    if needle in t:
        t = t.replace(needle, needle + f"\n\t\t\t\t{fid} /* {name} */,", 1)
    needle2 = "NA0000010000000000000007 /* ConnectionStore.swift in Sources */,"
    if needle2 in t:
        t = t.replace(needle2, needle2 + f"\n\t\t\t\t{bid} /* {name} in Sources */,", 1)
    p.write_text(t, encoding="utf-8")
    print("added", name)
