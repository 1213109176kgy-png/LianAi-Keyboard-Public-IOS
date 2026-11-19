#!/usr/bin/env python3
"""Generate a deterministic, dependency-free Xcode project for both native targets."""
from pathlib import Path
import hashlib, json, plistlib
r = Path(__file__).resolve().parent.parent
objects = {}
def ident(value): return hashlib.sha1(value.encode()).hexdigest()[:24].upper()
def obj(identifier, isa, **fields):
    key=ident(identifier);objects[key]={'isa':isa,**fields};return key
def ref(name): return ident(name)
def file(path, kind): return obj('file:'+path,'PBXFileReference',path=path,sourceTree='<group>',lastKnownFileType=kind)
def phase(identifier,isa,files,**kw): return obj(identifier,isa,buildActionMask=2147483647,files=files,runOnlyForDeploymentPostprocessing=0,**kw)
def build(name, fileID=None, product=None, **kw): return obj(name,'PBXBuildFile',**({'fileRef':fileID} if fileID else {'productRef':product}),**kw)
def configlist(name, settings):
    configs=[]
    for mode in ['Debug','Release']:
        cfg={**settings,'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if mode=='Debug' else '', 'ENABLE_TESTABILITY':'YES' if mode=='Debug' else 'NO'}
        configs.append(obj(name+':'+mode,'XCBuildConfiguration',name=mode,buildSettings=cfg,baseConfigurationReference=ref('file:config/Build.xcconfig')))
    return obj(name+':configs','XCConfigurationList',buildConfigurations=configs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
resources=[file('App/Assets.xcassets','folder.assetcatalog'),file('Resources/Rime','folder'),file('Resources/InputData','folder'),file('Resources/keyboard-click.wav','audio.wav')]
privacy=file('Resources/PrivacyInfo.xcprivacy','text.xml')
licenses=file('Licenses','folder')
base=file('config/Build.xcconfig','text.xcconfig')
packageIDs={name:obj('pkg:'+name,'XCLocalSwiftPackageReference',relativePath='Packages/'+name) for name in ['LianAiCore','KeyboardCore','RimeBridge']}
common={'SDKROOT':'iphoneos','ARCHS':'arm64','ONLY_ACTIVE_ARCH':'YES','IPHONEOS_DEPLOYMENT_TARGET':'18.0','SWIFT_VERSION':'6.0','SWIFT_STRICT_CONCURRENCY':'complete','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','GCC_C_LANGUAGE_STANDARD':'gnu17','CLANG_CXX_LANGUAGE_STANDARD':'gnu++17','CODE_SIGN_STYLE':'Automatic','TARGETED_DEVICE_FAMILY':'1,2','MARKETING_VERSION':'1.5.9','CURRENT_PROJECT_VERSION':'41','ENABLE_USER_SCRIPT_SANDBOXING':'YES','SWIFT_EMIT_LOC_STRINGS':'YES'}
sourceFiles={}
def source(path):
    if path not in sourceFiles:sourceFiles[path]=file(path,'sourcecode.swift')
    return sourceFiles[path]
shared=list(r.glob('SharedUI/*.swift'))
for name,folder,bundle,ext in [('LianAiKeyboard','App','com.lianai.keyboard.ios',False),('LianAiKeyboardExtension','Keyboard','com.lianai.keyboard.ios.Keyboard',True)]:
    paths=sorted(list(r.glob(folder+'/*.swift'))+shared)
    src=[build(name+':src:'+str(p.relative_to(r)),fileID=source(str(p.relative_to(r)))) for p in paths]
    deps=[];frameworks=[]
    for package,product in [('LianAiCore','LianAiCore'),('KeyboardCore','KeyboardCore'),('RimeBridge','RimeNative')]:
        productID=obj(name+':product:'+product,'XCSwiftPackageProductDependency',package=packageIDs[package],productName=product);deps.append(productID);frameworks.append(build(name+':link:'+product,product=productID))
    res=[build(name+':res:'+str(i),fileID=f) for i,f in enumerate(resources+[privacy]+([] if ext else [licenses]))]
    phases=[phase(name+':sources','PBXSourcesBuildPhase',src),phase(name+':frameworks','PBXFrameworksBuildPhase',frameworks),phase(name+':resources','PBXResourcesBuildPhase',res)]
    dependencies=[]
    if not ext:
        proxy=obj('extension:proxy','PBXContainerItemProxy',containerPortal=ref('project'),proxyType=1,remoteGlobalIDString=ref('target:LianAiKeyboardExtension'),remoteInfo='LianAiKeyboardExtension')
        dependencies=[obj('extension:dependency','PBXTargetDependency',target=ref('target:LianAiKeyboardExtension'),targetProxy=proxy)]
        embed=build('extension:embed',fileID=ref('extension:product'),settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})
        phases.append(phase('extension:embedphase','PBXCopyFilesBuildPhase',[embed],dstPath='',dstSubfolderSpec=13,name='Embed App Extensions'))
    product=obj('extension:product' if ext else 'app:product','PBXFileReference',explicitFileType='wrapper.app-extension' if ext else 'wrapper.application',path=name+('.appex' if ext else '.app'),sourceTree='BUILT_PRODUCTS_DIR',includeInIndex=0)
    settings={**common,'PRODUCT_BUNDLE_IDENTIFIER':bundle,'PRODUCT_NAME':'$(TARGET_NAME)','INFOPLIST_FILE':folder+'/Info.plist','CODE_SIGN_ENTITLEMENTS':folder+'/LianAi.entitlements','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks'+(' @executable_path/../../Frameworks' if ext else ''),'SWIFT_DEFAULT_ACTOR_ISOLATION':'MainActor'}
    if ext:settings.update({'APPLICATION_EXTENSION_API_ONLY':'YES','SKIP_INSTALL':'YES'})
    else:settings.update({'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon'})
    obj('target:'+name,'PBXNativeTarget',name=name,productName=name,productReference=product,productType='com.apple.product-type.app-extension' if ext else 'com.apple.product-type.application',buildConfigurationList=configlist(name,settings),buildPhases=phases,buildRules=[],dependencies=dependencies,packageProductDependencies=deps)
# Hosted tests exercise the actual bundled Rime binaries and resources.
name='LianAiKeyboardTests';src=[build(name+':'+str(p.relative_to(r)),fileID=source(str(p.relative_to(r)))) for p in sorted(r.glob('Tests/*Tests.swift'))]
prod=obj('tests:product','PBXFileReference',explicitFileType='wrapper.cfbundle',path=name+'.xctest',sourceTree='BUILT_PRODUCTS_DIR')
proxy=obj('tests:proxy','PBXContainerItemProxy',containerPortal=ref('project'),proxyType=1,remoteGlobalIDString=ref('target:LianAiKeyboard'),remoteInfo='LianAiKeyboard')
dep=obj('tests:dependency','PBXTargetDependency',target=ref('target:LianAiKeyboard'),targetProxy=proxy)
settings={**common,'PRODUCT_BUNDLE_IDENTIFIER':'com.lianai.keyboard.ios.Tests','PRODUCT_NAME':'$(TARGET_NAME)','GENERATE_INFOPLIST_FILE':'YES','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/LianAiKeyboard.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/LianAiKeyboard','BUNDLE_LOADER':'$(TEST_HOST)'}
obj('target:'+name,'PBXNativeTarget',name=name,productName=name,productReference=prod,productType='com.apple.product-type.bundle.unit-test',buildConfigurationList=configlist(name,settings),buildPhases=[phase(name+':sources','PBXSourcesBuildPhase',src),phase(name+':frameworks','PBXFrameworksBuildPhase',[])],buildRules=[],dependencies=[dep])
# Black-box UI tests run separately from engine-hosted tests.
name='LianAiKeyboardUITests'
src=[build(name+':'+str(p.relative_to(r)),fileID=source(str(p.relative_to(r)))) for p in sorted(r.glob('UITests/*.swift'))]
uiProduct=obj('uitests:product','PBXFileReference',explicitFileType='wrapper.cfbundle',path=name+'.xctest',sourceTree='BUILT_PRODUCTS_DIR')
settings={**common,'PRODUCT_BUNDLE_IDENTIFIER':'com.lianai.keyboard.ios.UITests','PRODUCT_NAME':'$(TARGET_NAME)','GENERATE_INFOPLIST_FILE':'YES','TEST_TARGET_NAME':'LianAiKeyboard'}
obj('target:'+name,'PBXNativeTarget',name=name,productName=name,productReference=uiProduct,productType='com.apple.product-type.bundle.ui-testing',buildConfigurationList=configlist(name,settings),buildPhases=[phase(name+':sources','PBXSourcesBuildPhase',src),phase(name+':frameworks','PBXFrameworksBuildPhase',[])],buildRules=[],dependencies=[dep])
products=obj('products','PBXGroup',name='Products',children=[ref('app:product'),ref('extension:product'),prod,uiProduct],sourceTree='<group>')
rootGroup=obj('root','PBXGroup',children=list(sourceFiles.values())+resources+[privacy,licenses,base,products],sourceTree='<group>')
obj('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'2700','TargetAttributes':{ref('target:LianAiKeyboardTests'):{'TestTargetID':ref('target:LianAiKeyboard')}}},buildConfigurationList=configlist('project',{'CLANG_ENABLE_MODULES':'YES','SWIFT_VERSION':'6.0','IPHONEOS_DEPLOYMENT_TARGET':'18.0'}),compatibilityVersion='Xcode 14.0',developmentRegion='zh-Hans',hasScannedForEncodings=0,knownRegions=['en','Base','zh-Hans'],mainGroup=rootGroup,productRefGroup=products,projectDirPath='',projectRoot='',targets=[ref('target:LianAiKeyboard'),ref('target:LianAiKeyboardExtension'),ref('target:LianAiKeyboardTests'),ref('target:LianAiKeyboardUITests')],packageReferences=list(packageIDs.values()))
def fmt(x,level=0):
    if isinstance(x,dict):return '{\n'+''.join('\t'*(level+1)+json.dumps(k,ensure_ascii=False)+' = '+fmt(v,level+1)+';\n' for k,v in x.items())+'\t'*level+'}'
    if isinstance(x,list):return '( '+', '.join(fmt(v,level) for v in x)+' )'
    if isinstance(x,int):return str(x)
    return x if x in objects else json.dumps(x,ensure_ascii=False)
p=r/'LianAiKeyboard.xcodeproj';p.mkdir(exist_ok=True)
(p/'project.pbxproj').write_text('// !$*UTF8*$!\n'+fmt({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':ref('project')})+'\n')
schemes=p/'xcshareddata/xcschemes';schemes.mkdir(parents=True,exist_ok=True)
def buildref(target,product):return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref("target:"+target)}" BuildableName="{product}" BlueprintName="{target}" ReferencedContainer="container:LianAiKeyboard.xcodeproj"/>'
appref=buildref('LianAiKeyboard','LianAiKeyboard.app');testref=buildref('LianAiKeyboardTests','LianAiKeyboardTests.xctest');uiref=buildref('LianAiKeyboardUITests','LianAiKeyboardUITests.xctest')
(schemes/'LianAiKeyboard.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?><Scheme LastUpgradeVersion="2700" version="1.7"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{appref}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{testref}</TestableReference><TestableReference skipped="NO">{uiref}</TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{appref}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release"><BuildableProductRunnable runnableDebuggingMode="0">{appref}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print('Generated',p)
