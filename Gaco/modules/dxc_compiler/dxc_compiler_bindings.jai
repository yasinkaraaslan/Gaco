//
// This file was auto-generated using the following command:
//
// jai generate.jai
//



DXC_CP_UTF8 :: 65001;
DXC_CP_UTF16 :: 1200;
DXC_CP_UTF32 :: 12000;

DXC_CP_ACP :: 0;

DXC_CP_WIDE :: DXC_CP_UTF16;

DXC_HASHFLAG_INCLUDES_SOURCE :: 1;

/// \brief Typedef for DxcCreateInstance function pointer.
///
/// This can be used with GetProcAddress to get the DxcCreateInstance function.
DxcCreateInstanceProc :: #type (rclsid: *IID, riid: *IID, ppv: **void) -> HRESULT #c_call;

/// \brief Typedef for DxcCreateInstance2 function pointer.
///
/// This can be used with GetProcAddress to get the DxcCreateInstance2 function.
DxcCreateInstance2Proc :: #type (pMalloc: *IMalloc, rclsid: *IID, riid: *IID, ppv: **void) -> HRESULT #c_call;

/// \brief Creates a single uninitialized object of the class associated with a
/// specified CLSID.
///
/// \param rclsid The CLSID associated with the data and code that will be used
/// to create the object.
///
/// \param riid A reference to the identifier of the interface to be used to
/// communicate with the object.
///
/// \param ppv Address of pointer variable that receives the interface pointer
/// requested in riid.  Upon successful return, *ppv contains the requested
/// interface pointer. Upon failure, *ppv contains NULL.
///
/// While this function is similar to CoCreateInstance, there is no COM
/// involvement.
DxcCreateInstance :: (rclsid: *IID, riid: *IID, ppv: **void) -> HRESULT #foreign dxcompiler;
DxcCreateInstance :: (rclsid: IID, riid: IID, ppv: **void) -> HRESULT #no_context {
    return DxcCreateInstance(*rclsid, *riid, ppv);
}

/// \brief Version of DxcCreateInstance that takes an IMalloc interface.
///
/// This can be used to create an instance of the compiler with a custom memory
/// allocator.
DxcCreateInstance2 :: (pMalloc: *IMalloc, rclsid: *IID, riid: *IID, ppv: **void) -> HRESULT #foreign dxcompiler;
DxcCreateInstance2 :: (pMalloc: *IMalloc, rclsid: IID, riid: IID, ppv: **void) -> HRESULT #no_context {
    return DxcCreateInstance2(pMalloc, *rclsid, *riid, ppv);
}

/// Hash digest type for ShaderHash.
DxcShaderHash :: struct {
    Flags:      u32; ///< DXC_HASHFLAG_*
    HashDigest: [16] u8; ///< The hash digest
}

/// \brief A sized buffer that can be passed in and out of DXC APIs.
///
/// This is an alias of ID3D10Blob and ID3DBlob.
IDxcBlob :: struct {
    #as using,except(vtable) iunknown: IUnknown;

    #overlay (iunknown) vtable: *IDxcBlob_VTable; // Overlay parent's vtable with IDxcBlob’s vtable
}
IDxcBlob_VTable :: struct #type_info_none {
    using vtable:     IUnknown_VTable;
    GetBufferPointer: #type (this: *IDxcBlob) -> *void #cpp_method;
    GetBufferSize:    #type (this: *IDxcBlob) -> SIZE_T #cpp_method;
}
IDxcBlob_GetBufferPointer :: inline (this: *IDxcBlob) -> *void { return this.vtable.GetBufferPointer(this); }

IDxcBlob_GetBufferSize :: inline (this: *IDxcBlob) -> SIZE_T { return this.vtable.GetBufferSize(this); }

vtable :: (obj: *IDxcBlob) -> *IDxcBlob_VTable { return obj.vtable; }


/// \brief A blob that might have a known encoding.
IDxcBlobEncoding :: struct {
    #as using,except(vtable) idxcblob: IDxcBlob;

    #overlay (idxcblob) vtable: *IDxcBlobEncoding_VTable; // Overlay parent's vtable with IDxcBlobEncoding’s vtable
}
IDxcBlobEncoding_VTable :: struct #type_info_none {
    using,except(vtable) vtable:      IDxcBlob_VTable;
    GetEncoding: #type (this: *IDxcBlobEncoding, pKnown: *BOOL, pCodePage: *u32) -> HRESULT #cpp_method;
}
IDxcBlobEncoding_GetEncoding :: inline (this: *IDxcBlobEncoding, pKnown: *BOOL, pCodePage: *u32) -> HRESULT { return this.vtable.GetEncoding(this, pKnown, pCodePage); }

vtable :: (obj: *IDxcBlobEncoding) -> *IDxcBlobEncoding_VTable { return obj.vtable; }


/// \brief A blob containing a null-terminated wide string.
///
/// This uses the native wide character encoding (utf16 on Windows, utf32 on
/// Linux).
///
/// The value returned by GetBufferSize() is the size of the buffer, in bytes,
/// including the null-terminator.
///
/// This interface is used to return output name strings DXC.  Other string
/// output blobs, such as errors/warnings, preprocessed HLSL, or other text are
/// returned using encodings based on the -encoding option passed to the
/// compiler.
IDxcBlobWide :: struct {
    #as using,except(vtable) idxcblobencoding: IDxcBlobEncoding;

    #overlay (idxcblobencoding) vtable: *IDxcBlobWide_VTable; // Overlay parent's vtable with IDxcBlobWide’s vtable
}
IDxcBlobWide_VTable :: struct #type_info_none {
    using,except(vtable) vtable:           IDxcBlobEncoding_VTable;
    GetStringPointer: #type (this: *IDxcBlobWide) -> *s16 #cpp_method;
    GetStringLength:  #type (this: *IDxcBlobWide) -> SIZE_T #cpp_method;
}
IDxcBlobWide_GetStringPointer :: inline (this: *IDxcBlobWide) -> *s16 { return this.vtable.GetStringPointer(this); }

IDxcBlobWide_GetStringLength :: inline (this: *IDxcBlobWide) -> SIZE_T { return this.vtable.GetStringLength(this); }

vtable :: (obj: *IDxcBlobWide) -> *IDxcBlobWide_VTable { return obj.vtable; }


/// \brief A blob containing a UTF-8 encoded string.
///
/// The value returned by GetBufferSize() is the size of the buffer, in bytes,
/// including the null-terminator.
///
/// Depending on the -encoding option passed to the compiler, this interface is
/// used to return string output blobs, such as errors/warnings, preprocessed
/// HLSL, or other text. Output name strings always use IDxcBlobWide.
IDxcBlobUtf8 :: struct {
    #as using,except(vtable) idxcblobencoding: IDxcBlobEncoding;

    #overlay (idxcblobencoding) vtable: *IDxcBlobUtf8_VTable; // Overlay parent's vtable with IDxcBlobUtf8’s vtable
}
IDxcBlobUtf8_VTable :: struct #type_info_none {
    using,except(vtable) vtable:           IDxcBlobEncoding_VTable;
    GetStringPointer: #type (this: *IDxcBlobUtf8) -> *u8 #cpp_method;
    GetStringLength:  #type (this: *IDxcBlobUtf8) -> SIZE_T #cpp_method;
}
IDxcBlobUtf8_GetStringPointer :: inline (this: *IDxcBlobUtf8) -> *u8 { return this.vtable.GetStringPointer(this); }

IDxcBlobUtf8_GetStringLength :: inline (this: *IDxcBlobUtf8) -> SIZE_T { return this.vtable.GetStringLength(this); }

vtable :: (obj: *IDxcBlobUtf8) -> *IDxcBlobUtf8_VTable { return obj.vtable; }


/// IDxcBlobUtf16 is a legacy alias for IDxcBlobWide on Win32.
IDxcBlobUtf16 :: IDxcBlobWide;

/// \brief Interface for handling include directives.
///
/// This interface can be implemented to customize handling of include
/// directives.
///
/// Use IDxcUtils::CreateDefaultIncludeHandler to create a default
/// implementation that reads include files from the filesystem.
///
IDxcIncludeHandler :: struct {
    #as using,except(vtable) iunknown: IUnknown;

    #overlay (iunknown) vtable: *IDxcIncludeHandler_VTable; // Overlay parent's vtable with IDxcIncludeHandler’s vtable
}
IDxcIncludeHandler_VTable :: struct #type_info_none {
    using vtable: IUnknown_VTable;
    LoadSource:   #type (this: *IDxcIncludeHandler, pFilename: *s16, ppIncludeSource: **IDxcBlob) -> HRESULT #cpp_method;
}
IDxcIncludeHandler_LoadSource :: inline (this: *IDxcIncludeHandler, pFilename: *s16, ppIncludeSource: **IDxcBlob) -> HRESULT { return this.vtable.LoadSource(this, pFilename, ppIncludeSource); }

vtable :: (obj: *IDxcIncludeHandler) -> *IDxcIncludeHandler_VTable { return obj.vtable; }


/// \brief Structure for supplying bytes or text input to Dxc APIs.
DxcBuffer :: struct {
    /// \brief Pointer to the start of the buffer.
    Ptr:      *void;

    /// \brief Size of the buffer in bytes.
    Size:     SIZE_T;

    /// \brief Encoding of the buffer.
    ///
    /// Use Encoding = 0 for non-text bytes, ANSI text, or unknown with BOM.
    Encoding: u32;
}

/// \brief Structure for supplying bytes or text input to Dxc APIs.
DxcText :: DxcBuffer;

/// \brief Structure for supplying defines to Dxc APIs.
DxcDefine :: struct {
    Name:  *s16; ///< The define name.
    Value: *s16; ///< Optional value for the define.
}

/// \brief Interface for managing arguments passed to DXC.
///
/// Use IDxcUtils::BuildArguments to create an instance of this interface.
IDxcCompilerArgs :: struct {
    #as using,except(vtable) iunknown: IUnknown;

    #overlay (iunknown) vtable: *IDxcCompilerArgs_VTable; // Overlay parent's vtable with IDxcCompilerArgs’s vtable
}
IDxcCompilerArgs_VTable :: struct #type_info_none {
    using vtable:     IUnknown_VTable;
    GetArguments:     #type (this: *IDxcCompilerArgs) -> **s16 #cpp_method;
    GetCount:         #type (this: *IDxcCompilerArgs) -> u32 #cpp_method;
    AddArguments:     #type (this: *IDxcCompilerArgs, pArguments: **s16, argCount: u32) -> HRESULT #cpp_method;
    AddArgumentsUTF8: #type (this: *IDxcCompilerArgs, pArguments: **u8, argCount: u32) -> HRESULT #cpp_method;
    AddDefines:       #type (this: *IDxcCompilerArgs, pDefines: *DxcDefine, defineCount: u32) -> HRESULT #cpp_method;
}
IDxcCompilerArgs_GetArguments :: inline (this: *IDxcCompilerArgs) -> **s16 { return this.vtable.GetArguments(this); }

IDxcCompilerArgs_GetCount :: inline (this: *IDxcCompilerArgs) -> u32 { return this.vtable.GetCount(this); }

IDxcCompilerArgs_AddArguments :: inline (this: *IDxcCompilerArgs, pArguments: **s16, argCount: u32) -> HRESULT { return this.vtable.AddArguments(this, pArguments, argCount); }

IDxcCompilerArgs_AddArgumentsUTF8 :: inline (this: *IDxcCompilerArgs, pArguments: **u8, argCount: u32) -> HRESULT { return this.vtable.AddArgumentsUTF8(this, pArguments, argCount); }

IDxcCompilerArgs_AddDefines :: inline (this: *IDxcCompilerArgs, pDefines: *DxcDefine, defineCount: u32) -> HRESULT { return this.vtable.AddDefines(this, pDefines, defineCount); }

vtable :: (obj: *IDxcCompilerArgs) -> *IDxcCompilerArgs_VTable { return obj.vtable; }


//////////////////////////
// Legacy Interfaces
/////////////////////////
IDxcLibrary :: struct {
    #as using,except(vtable) iunknown: IUnknown;

    #overlay (iunknown) vtable: *IDxcLibrary_VTable; // Overlay parent's vtable with IDxcLibrary’s vtable
}
IDxcLibrary_VTable :: struct #type_info_none {
    using vtable:                     IUnknown_VTable;
    SetMalloc:                        #type (this: *IDxcLibrary, pMalloc: *IMalloc) -> HRESULT #cpp_method;
    CreateBlobFromBlob:               #type (this: *IDxcLibrary, pBlob: *IDxcBlob, offset: u32, length: u32, ppResult: **IDxcBlob) -> HRESULT #cpp_method;
    CreateBlobFromFile:               #type (this: *IDxcLibrary, pFileName: *s16, codePage: *u32, pBlobEncoding: **IDxcBlobEncoding) -> HRESULT #cpp_method;
    CreateBlobWithEncodingFromPinned: #type (this: *IDxcLibrary, pText: *void, size: u32, codePage: u32, pBlobEncoding: **IDxcBlobEncoding) -> HRESULT #cpp_method;
    CreateBlobWithEncodingOnHeapCopy: #type (this: *IDxcLibrary, pText: *void, size: u32, codePage: u32, pBlobEncoding: **IDxcBlobEncoding) -> HRESULT #cpp_method;
    CreateBlobWithEncodingOnMalloc:   #type (this: *IDxcLibrary, pText: *void, pIMalloc: *IMalloc, size: u32, codePage: u32, pBlobEncoding: **IDxcBlobEncoding) -> HRESULT #cpp_method;
    CreateIncludeHandler:             #type (this: *IDxcLibrary, ppResult: **IDxcIncludeHandler) -> HRESULT #cpp_method;
    CreateStreamFromBlobReadOnly:     #type (this: *IDxcLibrary, pBlob: *IDxcBlob, ppStream: **IStream) -> HRESULT #cpp_method;
    GetBlobAsUtf8:                    #type (this: *IDxcLibrary, pBlob: *IDxcBlob, pBlobEncoding: **IDxcBlobEncoding) -> HRESULT #cpp_method;
    GetBlobAsWide:                    #type (this: *IDxcLibrary, pBlob: *IDxcBlob, pBlobEncoding: **IDxcBlobEncoding) -> HRESULT #cpp_method;
}
IDxcLibrary_SetMalloc :: inline (this: *IDxcLibrary, pMalloc: *IMalloc) -> HRESULT { return this.vtable.SetMalloc(this, pMalloc); }

IDxcLibrary_CreateBlobFromBlob :: inline (this: *IDxcLibrary, pBlob: *IDxcBlob, offset: u32, length: u32, ppResult: **IDxcBlob) -> HRESULT { return this.vtable.CreateBlobFromBlob(this, pBlob, offset, length, ppResult); }

IDxcLibrary_CreateBlobFromFile :: inline (this: *IDxcLibrary, pFileName: *s16, codePage: *u32, pBlobEncoding: **IDxcBlobEncoding) -> HRESULT { return this.vtable.CreateBlobFromFile(this, pFileName, codePage, pBlobEncoding); }

IDxcLibrary_CreateBlobWithEncodingFromPinned :: inline (this: *IDxcLibrary, pText: *void, size: u32, codePage: u32, pBlobEncoding: **IDxcBlobEncoding) -> HRESULT { return this.vtable.CreateBlobWithEncodingFromPinned(this, pText, size, codePage, pBlobEncoding); }

IDxcLibrary_CreateBlobWithEncodingOnHeapCopy :: inline (this: *IDxcLibrary, pText: *void, size: u32, codePage: u32, pBlobEncoding: **IDxcBlobEncoding) -> HRESULT { return this.vtable.CreateBlobWithEncodingOnHeapCopy(this, pText, size, codePage, pBlobEncoding); }

IDxcLibrary_CreateBlobWithEncodingOnMalloc :: inline (this: *IDxcLibrary, pText: *void, pIMalloc: *IMalloc, size: u32, codePage: u32, pBlobEncoding: **IDxcBlobEncoding) -> HRESULT { return this.vtable.CreateBlobWithEncodingOnMalloc(this, pText, pIMalloc, size, codePage, pBlobEncoding); }

IDxcLibrary_CreateIncludeHandler :: inline (this: *IDxcLibrary, ppResult: **IDxcIncludeHandler) -> HRESULT { return this.vtable.CreateIncludeHandler(this, ppResult); }

IDxcLibrary_CreateStreamFromBlobReadOnly :: inline (this: *IDxcLibrary, pBlob: *IDxcBlob, ppStream: **IStream) -> HRESULT { return this.vtable.CreateStreamFromBlobReadOnly(this, pBlob, ppStream); }

IDxcLibrary_GetBlobAsUtf8 :: inline (this: *IDxcLibrary, pBlob: *IDxcBlob, pBlobEncoding: **IDxcBlobEncoding) -> HRESULT { return this.vtable.GetBlobAsUtf8(this, pBlob, pBlobEncoding); }

IDxcLibrary_GetBlobAsWide :: inline (this: *IDxcLibrary, pBlob: *IDxcBlob, pBlobEncoding: **IDxcBlobEncoding) -> HRESULT { return this.vtable.GetBlobAsWide(this, pBlob, pBlobEncoding); }

vtable :: (obj: *IDxcLibrary) -> *IDxcLibrary_VTable { return obj.vtable; }


/// \brief The results of a DXC operation.
///
/// Note: IDxcResult replaces IDxcOperationResult and should be used wherever
/// possible.
IDxcOperationResult :: struct {
    #as using,except(vtable) iunknown: IUnknown;

    #overlay (iunknown) vtable: *IDxcOperationResult_VTable; // Overlay parent's vtable with IDxcOperationResult’s vtable
}
IDxcOperationResult_VTable :: struct #type_info_none {
    using vtable:   IUnknown_VTable;
    GetStatus:      #type (this: *IDxcOperationResult, pStatus: *HRESULT) -> HRESULT #cpp_method;
    GetResult:      #type (this: *IDxcOperationResult, ppResult: **IDxcBlob) -> HRESULT #cpp_method;
    GetErrorBuffer: #type (this: *IDxcOperationResult, ppErrors: **IDxcBlobEncoding) -> HRESULT #cpp_method;
}
IDxcOperationResult_GetStatus :: inline (this: *IDxcOperationResult, pStatus: *HRESULT) -> HRESULT { return this.vtable.GetStatus(this, pStatus); }

IDxcOperationResult_GetResult :: inline (this: *IDxcOperationResult, ppResult: **IDxcBlob) -> HRESULT { return this.vtable.GetResult(this, ppResult); }

IDxcOperationResult_GetErrorBuffer :: inline (this: *IDxcOperationResult, ppErrors: **IDxcBlobEncoding) -> HRESULT { return this.vtable.GetErrorBuffer(this, ppErrors); }

vtable :: (obj: *IDxcOperationResult) -> *IDxcOperationResult_VTable { return obj.vtable; }


/// \deprecated Please use IDxcCompiler3 instead.
IDxcCompiler :: struct {
    #as using,except(vtable) iunknown: IUnknown;

    #overlay (iunknown) vtable: *IDxcCompiler_VTable; // Overlay parent's vtable with IDxcCompiler’s vtable
}
IDxcCompiler_VTable :: struct #type_info_none {
    using vtable: IUnknown_VTable;
    Compile:      #type (this: *IDxcCompiler, pSource: *IDxcBlob, pSourceName: *s16, pEntryPoint: *s16, pTargetProfile: *s16, pArguments: **s16, argCount: u32, pDefines: *DxcDefine, defineCount: u32, pIncludeHandler: *IDxcIncludeHandler, ppResult: **IDxcOperationResult) -> HRESULT #cpp_method;
    Preprocess:   #type (this: *IDxcCompiler, pSource: *IDxcBlob, pSourceName: *s16, pArguments: **s16, argCount: u32, pDefines: *DxcDefine, defineCount: u32, pIncludeHandler: *IDxcIncludeHandler, ppResult: **IDxcOperationResult) -> HRESULT #cpp_method;
    Disassemble:  #type (this: *IDxcCompiler, pSource: *IDxcBlob, ppDisassembly: **IDxcBlobEncoding) -> HRESULT #cpp_method;
}
IDxcCompiler_Compile :: inline (this: *IDxcCompiler, pSource: *IDxcBlob, pSourceName: *s16, pEntryPoint: *s16, pTargetProfile: *s16, pArguments: **s16, argCount: u32, pDefines: *DxcDefine, defineCount: u32, pIncludeHandler: *IDxcIncludeHandler, ppResult: **IDxcOperationResult) -> HRESULT { return this.vtable.Compile(this, pSource, pSourceName, pEntryPoint, pTargetProfile, pArguments, argCount, pDefines, defineCount, pIncludeHandler, ppResult); }

IDxcCompiler_Preprocess :: inline (this: *IDxcCompiler, pSource: *IDxcBlob, pSourceName: *s16, pArguments: **s16, argCount: u32, pDefines: *DxcDefine, defineCount: u32, pIncludeHandler: *IDxcIncludeHandler, ppResult: **IDxcOperationResult) -> HRESULT { return this.vtable.Preprocess(this, pSource, pSourceName, pArguments, argCount, pDefines, defineCount, pIncludeHandler, ppResult); }

IDxcCompiler_Disassemble :: inline (this: *IDxcCompiler, pSource: *IDxcBlob, ppDisassembly: **IDxcBlobEncoding) -> HRESULT { return this.vtable.Disassemble(this, pSource, ppDisassembly); }

vtable :: (obj: *IDxcCompiler) -> *IDxcCompiler_VTable { return obj.vtable; }


/// \deprecated Please use IDxcCompiler3 instead.
IDxcCompiler2 :: struct {
    #as using,except(vtable) idxccompiler: IDxcCompiler;

    #overlay (idxccompiler) vtable: *IDxcCompiler2_VTable; // Overlay parent's vtable with IDxcCompiler2’s vtable
}
IDxcCompiler2_VTable :: struct #type_info_none {
    using,except(vtable) vtable:           IDxcCompiler_VTable;
    CompileWithDebug: #type (this: *IDxcCompiler2, pSource: *IDxcBlob, pSourceName: *s16, pEntryPoint: *s16, pTargetProfile: *s16, pArguments: **s16, argCount: u32, pDefines: *DxcDefine, defineCount: u32, pIncludeHandler: *IDxcIncludeHandler, ppResult: **IDxcOperationResult, ppDebugBlobName: **s16, ppDebugBlob: **IDxcBlob) -> HRESULT #cpp_method;
}
IDxcCompiler2_CompileWithDebug :: inline (this: *IDxcCompiler2, pSource: *IDxcBlob, pSourceName: *s16, pEntryPoint: *s16, pTargetProfile: *s16, pArguments: **s16, argCount: u32, pDefines: *DxcDefine, defineCount: u32, pIncludeHandler: *IDxcIncludeHandler, ppResult: **IDxcOperationResult, ppDebugBlobName: **s16, ppDebugBlob: **IDxcBlob) -> HRESULT { return this.vtable.CompileWithDebug(this, pSource, pSourceName, pEntryPoint, pTargetProfile, pArguments, argCount, pDefines, defineCount, pIncludeHandler, ppResult, ppDebugBlobName, ppDebugBlob); }

vtable :: (obj: *IDxcCompiler2) -> *IDxcCompiler2_VTable { return obj.vtable; }


/// \brief DXC linker interface.
///
/// Use DxcCreateInstance with CLSID_DxcLinker to obtain an instance of this
/// interface.
IDxcLinker :: struct {
    #as using,except(vtable) iunknown: IUnknown;

    #overlay (iunknown) vtable: *IDxcLinker_VTable; // Overlay parent's vtable with IDxcLinker’s vtable
}
IDxcLinker_VTable :: struct #type_info_none {
    using vtable:    IUnknown_VTable;
    RegisterLibrary: #type (this: *IDxcLinker, pLibName: *s16, pLib: *IDxcBlob) -> HRESULT #cpp_method;
    Link:            #type (this: *IDxcLinker, pEntryName: *s16, pTargetProfile: *s16, pLibNames: **s16, libCount: u32, pArguments: **s16, argCount: u32, ppResult: **IDxcOperationResult) -> HRESULT #cpp_method;
}
IDxcLinker_RegisterLibrary :: inline (this: *IDxcLinker, pLibName: *s16, pLib: *IDxcBlob) -> HRESULT { return this.vtable.RegisterLibrary(this, pLibName, pLib); }

IDxcLinker_Link :: inline (this: *IDxcLinker, pEntryName: *s16, pTargetProfile: *s16, pLibNames: **s16, libCount: u32, pArguments: **s16, argCount: u32, ppResult: **IDxcOperationResult) -> HRESULT { return this.vtable.Link(this, pEntryName, pTargetProfile, pLibNames, libCount, pArguments, argCount, ppResult); }

vtable :: (obj: *IDxcLinker) -> *IDxcLinker_VTable { return obj.vtable; }


/////////////////////////
// Latest interfaces. Please use these.
////////////////////////
IDxcUtils :: struct {
    #as using,except(vtable) iunknown: IUnknown;

    #overlay (iunknown) vtable: *IDxcUtils_VTable; // Overlay parent's vtable with IDxcUtils’s vtable
}
IDxcUtils_VTable :: struct #type_info_none {
    using vtable:                 IUnknown_VTable;
    CreateBlobFromBlob:           #type (this: *IDxcUtils, pBlob: *IDxcBlob, offset: u32, length: u32, ppResult: **IDxcBlob) -> HRESULT #cpp_method;
    CreateBlobFromPinned:         #type (this: *IDxcUtils, pData: *void, size: u32, codePage: u32, ppBlobEncoding: **IDxcBlobEncoding) -> HRESULT #cpp_method;
    MoveToBlob:                   #type (this: *IDxcUtils, pData: *void, pIMalloc: *IMalloc, size: u32, codePage: u32, ppBlobEncoding: **IDxcBlobEncoding) -> HRESULT #cpp_method;
    CreateBlob:                   #type (this: *IDxcUtils, pData: *void, size: u32, codePage: u32, ppBlobEncoding: **IDxcBlobEncoding) -> HRESULT #cpp_method;
    LoadFile:                     #type (this: *IDxcUtils, pFileName: *s16, pCodePage: *u32, ppBlobEncoding: **IDxcBlobEncoding) -> HRESULT #cpp_method;
    CreateReadOnlyStreamFromBlob: #type (this: *IDxcUtils, pBlob: *IDxcBlob, ppStream: **IStream) -> HRESULT #cpp_method;
    CreateDefaultIncludeHandler:  #type (this: *IDxcUtils, ppResult: **IDxcIncludeHandler) -> HRESULT #cpp_method;
    GetBlobAsUtf8:                #type (this: *IDxcUtils, pBlob: *IDxcBlob, ppBlobEncoding: **IDxcBlobUtf8) -> HRESULT #cpp_method;
    GetBlobAsWide:                #type (this: *IDxcUtils, pBlob: *IDxcBlob, ppBlobEncoding: **IDxcBlobWide) -> HRESULT #cpp_method;
    GetDxilContainerPart:         #type (this: *IDxcUtils, pShader: *DxcBuffer, DxcPart: u32, ppPartData: **void, pPartSizeInBytes: *u32) -> HRESULT #cpp_method;
    CreateReflection:             #type (this: *IDxcUtils, pData: *DxcBuffer, iid: *IID, ppvReflection: **void) -> HRESULT #cpp_method;
    BuildArguments:               #type (this: *IDxcUtils, pSourceName: *s16, pEntryPoint: *s16, pTargetProfile: *s16, pArguments: **s16, argCount: u32, pDefines: *DxcDefine, defineCount: u32, ppArgs: **IDxcCompilerArgs) -> HRESULT #cpp_method;
    GetPDBContents:               #type (this: *IDxcUtils, pPDBBlob: *IDxcBlob, ppHash: **IDxcBlob, ppContainer: **IDxcBlob) -> HRESULT #cpp_method;
}
IDxcUtils_CreateBlobFromBlob :: inline (this: *IDxcUtils, pBlob: *IDxcBlob, offset: u32, length: u32, ppResult: **IDxcBlob) -> HRESULT { return this.vtable.CreateBlobFromBlob(this, pBlob, offset, length, ppResult); }

IDxcUtils_CreateBlobFromPinned :: inline (this: *IDxcUtils, pData: *void, size: u32, codePage: u32, ppBlobEncoding: **IDxcBlobEncoding) -> HRESULT { return this.vtable.CreateBlobFromPinned(this, pData, size, codePage, ppBlobEncoding); }

IDxcUtils_MoveToBlob :: inline (this: *IDxcUtils, pData: *void, pIMalloc: *IMalloc, size: u32, codePage: u32, ppBlobEncoding: **IDxcBlobEncoding) -> HRESULT { return this.vtable.MoveToBlob(this, pData, pIMalloc, size, codePage, ppBlobEncoding); }

IDxcUtils_CreateBlob :: inline (this: *IDxcUtils, pData: *void, size: u32, codePage: u32, ppBlobEncoding: **IDxcBlobEncoding) -> HRESULT { return this.vtable.CreateBlob(this, pData, size, codePage, ppBlobEncoding); }

IDxcUtils_LoadFile :: inline (this: *IDxcUtils, pFileName: *s16, pCodePage: *u32, ppBlobEncoding: **IDxcBlobEncoding) -> HRESULT { return this.vtable.LoadFile(this, pFileName, pCodePage, ppBlobEncoding); }

IDxcUtils_CreateReadOnlyStreamFromBlob :: inline (this: *IDxcUtils, pBlob: *IDxcBlob, ppStream: **IStream) -> HRESULT { return this.vtable.CreateReadOnlyStreamFromBlob(this, pBlob, ppStream); }

IDxcUtils_CreateDefaultIncludeHandler :: inline (this: *IDxcUtils, ppResult: **IDxcIncludeHandler) -> HRESULT { return this.vtable.CreateDefaultIncludeHandler(this, ppResult); }

IDxcUtils_GetBlobAsUtf8 :: inline (this: *IDxcUtils, pBlob: *IDxcBlob, ppBlobEncoding: **IDxcBlobUtf8) -> HRESULT { return this.vtable.GetBlobAsUtf8(this, pBlob, ppBlobEncoding); }

IDxcUtils_GetBlobAsWide :: inline (this: *IDxcUtils, pBlob: *IDxcBlob, ppBlobEncoding: **IDxcBlobWide) -> HRESULT { return this.vtable.GetBlobAsWide(this, pBlob, ppBlobEncoding); }

IDxcUtils_GetDxilContainerPart :: inline (this: *IDxcUtils, pShader: *DxcBuffer, DxcPart: u32, ppPartData: **void, pPartSizeInBytes: *u32) -> HRESULT { return this.vtable.GetDxilContainerPart(this, pShader, DxcPart, ppPartData, pPartSizeInBytes); }

IDxcUtils_CreateReflection :: inline (this: *IDxcUtils, pData: *DxcBuffer, iid: *IID, ppvReflection: **void) -> HRESULT { return this.vtable.CreateReflection(this, pData, iid, ppvReflection); }

IDxcUtils_BuildArguments :: inline (this: *IDxcUtils, pSourceName: *s16, pEntryPoint: *s16, pTargetProfile: *s16, pArguments: **s16, argCount: u32, pDefines: *DxcDefine, defineCount: u32, ppArgs: **IDxcCompilerArgs) -> HRESULT { return this.vtable.BuildArguments(this, pSourceName, pEntryPoint, pTargetProfile, pArguments, argCount, pDefines, defineCount, ppArgs); }

IDxcUtils_GetPDBContents :: inline (this: *IDxcUtils, pPDBBlob: *IDxcBlob, ppHash: **IDxcBlob, ppContainer: **IDxcBlob) -> HRESULT { return this.vtable.GetPDBContents(this, pPDBBlob, ppHash, ppContainer); }

vtable :: (obj: *IDxcUtils) -> *IDxcUtils_VTable { return obj.vtable; }


/// \brief Specifies the kind of output to retrieve from a IDxcResult.
///
/// Note: text outputs returned from version 2 APIs are UTF-8 or UTF-16 based on
/// the -encoding option passed to the compiler.
DXC_OUT_KIND :: enum s32 {
    NONE           :: 0;
    OBJECT         :: 1;
    ERRORS         :: 2;
    PDB            :: 3;
    SHADER_HASH    :: 4;

    DISASSEMBLY    :: 5;
    HLSL           :: 6;

    TEXT           :: 7;

    REFLECTION     :: 8;
    ROOT_SIGNATURE :: 9;
    EXTRA_OUTPUTS  :: 10;
    REMARKS        :: 11;

    TIME_REPORT    :: 12;

    TIME_TRACE     :: 13;

    LAST           :: 13;

    NUM_ENUMS      :: 14;
    FORCE_DWORD    :: -1;

    DXC_OUT_NONE           :: NONE;
    DXC_OUT_OBJECT         :: OBJECT;
    DXC_OUT_ERRORS         :: ERRORS;
    DXC_OUT_PDB            :: PDB;
    DXC_OUT_SHADER_HASH    :: SHADER_HASH;

    DXC_OUT_DISASSEMBLY    :: DISASSEMBLY;
    DXC_OUT_HLSL           :: HLSL;

    DXC_OUT_TEXT           :: TEXT;

    DXC_OUT_REFLECTION     :: REFLECTION;
    DXC_OUT_ROOT_SIGNATURE :: ROOT_SIGNATURE;
    DXC_OUT_EXTRA_OUTPUTS  :: EXTRA_OUTPUTS;
    DXC_OUT_REMARKS        :: REMARKS;

    DXC_OUT_TIME_REPORT    :: TIME_REPORT;

    DXC_OUT_TIME_TRACE     :: TIME_TRACE;

    DXC_OUT_LAST           :: LAST;

    DXC_OUT_NUM_ENUMS      :: NUM_ENUMS;
    DXC_OUT_FORCE_DWORD    :: FORCE_DWORD;
}

/// \brief Result of a DXC operation.
///
/// DXC operations may have multiple outputs, such as a shader object and
/// errors. This interface provides access to the outputs.
IDxcResult :: struct {
    #as using,except(vtable) idxcoperationresult: IDxcOperationResult;

    #overlay (idxcoperationresult) vtable: *IDxcResult_VTable; // Overlay parent's vtable with IDxcResult’s vtable
}
IDxcResult_VTable :: struct #type_info_none {
    using,except(vtable) vtable:           IDxcOperationResult_VTable;
    HasOutput:        #type (this: *IDxcResult, dxcOutKind: DXC_OUT_KIND) -> BOOL #cpp_method;
    GetOutput:        #type (this: *IDxcResult, dxcOutKind: DXC_OUT_KIND, iid: *IID, ppvObject: **void, ppOutputName: **IDxcBlobWide) -> HRESULT #cpp_method;
    GetNumOutputs:    #type (this: *IDxcResult) -> u32 #cpp_method;
    GetOutputByIndex: #type (this: *IDxcResult, Index: u32) -> DXC_OUT_KIND #cpp_method;
    PrimaryOutput:    #type (this: *IDxcResult) -> DXC_OUT_KIND #cpp_method;
}
IDxcResult_HasOutput :: inline (this: *IDxcResult, dxcOutKind: DXC_OUT_KIND) -> BOOL { return this.vtable.HasOutput(this, dxcOutKind); }

IDxcResult_GetOutput :: inline (this: *IDxcResult, dxcOutKind: DXC_OUT_KIND, iid: *IID, ppvObject: **void, ppOutputName: **IDxcBlobWide) -> HRESULT { return this.vtable.GetOutput(this, dxcOutKind, iid, ppvObject, ppOutputName); }

IDxcResult_GetNumOutputs :: inline (this: *IDxcResult) -> u32 { return this.vtable.GetNumOutputs(this); }

IDxcResult_GetOutputByIndex :: inline (this: *IDxcResult, Index: u32) -> DXC_OUT_KIND { return this.vtable.GetOutputByIndex(this, Index); }

IDxcResult_PrimaryOutput :: inline (this: *IDxcResult) -> DXC_OUT_KIND { return this.vtable.PrimaryOutput(this); }

vtable :: (obj: *IDxcResult) -> *IDxcResult_VTable { return obj.vtable; }


/// \brief Additional outputs from a DXC operation.
///
/// This can be used to obtain outputs that don't have an explicit DXC_OUT_KIND.
/// Use DXC_OUT_EXTRA_OUTPUTS to obtain instances of this.
IDxcExtraOutputs :: struct {
    #as using,except(vtable) iunknown: IUnknown;

    #overlay (iunknown) vtable: *IDxcExtraOutputs_VTable; // Overlay parent's vtable with IDxcExtraOutputs’s vtable
}
IDxcExtraOutputs_VTable :: struct #type_info_none {
    using vtable:   IUnknown_VTable;
    GetOutputCount: #type (this: *IDxcExtraOutputs) -> u32 #cpp_method;
    GetOutput:      #type (this: *IDxcExtraOutputs, uIndex: u32, iid: *IID, ppvObject: **void, ppOutputType: **IDxcBlobWide, ppOutputName: **IDxcBlobWide) -> HRESULT #cpp_method;
}
IDxcExtraOutputs_GetOutputCount :: inline (this: *IDxcExtraOutputs) -> u32 { return this.vtable.GetOutputCount(this); }

IDxcExtraOutputs_GetOutput :: inline (this: *IDxcExtraOutputs, uIndex: u32, iid: *IID, ppvObject: **void, ppOutputType: **IDxcBlobWide, ppOutputName: **IDxcBlobWide) -> HRESULT { return this.vtable.GetOutput(this, uIndex, iid, ppvObject, ppOutputType, ppOutputName); }

vtable :: (obj: *IDxcExtraOutputs) -> *IDxcExtraOutputs_VTable { return obj.vtable; }


/// \brief Interface to the DirectX Shader Compiler.
///
/// Use DxcCreateInstance with CLSID_DxcCompiler to obtain an instance of this
/// interface.
IDxcCompiler3 :: struct {
    #as using,except(vtable) iunknown: IUnknown;

    #overlay (iunknown) vtable: *IDxcCompiler3_VTable; // Overlay parent's vtable with IDxcCompiler3’s vtable
}
IDxcCompiler3_VTable :: struct #type_info_none {
    using vtable: IUnknown_VTable;
    Compile:      #type (this: *IDxcCompiler3, pSource: *DxcBuffer, pArguments: **s16, argCount: u32, pIncludeHandler: *IDxcIncludeHandler, riid: *IID, ppResult: **void) -> HRESULT #cpp_method;
    Disassemble:  #type (this: *IDxcCompiler3, pObject: *DxcBuffer, riid: *IID, ppResult: **void) -> HRESULT #cpp_method;
}
IDxcCompiler3_Compile :: inline (this: *IDxcCompiler3, pSource: *DxcBuffer, pArguments: **s16, argCount: u32, pIncludeHandler: *IDxcIncludeHandler, riid: *IID, ppResult: **void) -> HRESULT { return this.vtable.Compile(this, pSource, pArguments, argCount, pIncludeHandler, riid, ppResult); }

IDxcCompiler3_Disassemble :: inline (this: *IDxcCompiler3, pObject: *DxcBuffer, riid: *IID, ppResult: **void) -> HRESULT { return this.vtable.Disassemble(this, pObject, riid, ppResult); }

vtable :: (obj: *IDxcCompiler3) -> *IDxcCompiler3_VTable { return obj.vtable; }


DxcValidatorFlags_Default: u32 : 0;
DxcValidatorFlags_InPlaceEdit: u32 : 1;

DxcValidatorFlags_RootSignatureOnly: u32 : 2;
DxcValidatorFlags_ModuleOnly: u32 : 4;
DxcValidatorFlags_ValidMask: u32 : 7;

/// \brief Interface to DXC shader validator.
///
/// Use DxcCreateInstance with CLSID_DxcValidator to obtain an instance of this.
IDxcValidator :: struct {
    #as using,except(vtable) iunknown: IUnknown;

    #overlay (iunknown) vtable: *IDxcValidator_VTable; // Overlay parent's vtable with IDxcValidator’s vtable
}
IDxcValidator_VTable :: struct #type_info_none {
    using vtable: IUnknown_VTable;
    Validate:     #type (this: *IDxcValidator, pShader: *IDxcBlob, Flags: u32, ppResult: **IDxcOperationResult) -> HRESULT #cpp_method;
}
IDxcValidator_Validate :: inline (this: *IDxcValidator, pShader: *IDxcBlob, Flags: u32, ppResult: **IDxcOperationResult) -> HRESULT { return this.vtable.Validate(this, pShader, Flags, ppResult); }

vtable :: (obj: *IDxcValidator) -> *IDxcValidator_VTable { return obj.vtable; }


/// \brief Interface to DXC shader validator.
///
/// Use DxcCreateInstance with CLSID_DxcValidator to obtain an instance of this.
IDxcValidator2 :: struct {
    #as using,except(vtable) idxcvalidator: IDxcValidator;

    #overlay (idxcvalidator) vtable: *IDxcValidator2_VTable; // Overlay parent's vtable with IDxcValidator2’s vtable
}
IDxcValidator2_VTable :: struct #type_info_none {
    using,except(vtable) vtable:            IDxcValidator_VTable;
    ValidateWithDebug: #type (this: *IDxcValidator2, pShader: *IDxcBlob, Flags: u32, pOptDebugBitcode: *DxcBuffer, ppResult: **IDxcOperationResult) -> HRESULT #cpp_method;
}
IDxcValidator2_ValidateWithDebug :: inline (this: *IDxcValidator2, pShader: *IDxcBlob, Flags: u32, pOptDebugBitcode: *DxcBuffer, ppResult: **IDxcOperationResult) -> HRESULT { return this.vtable.ValidateWithDebug(this, pShader, Flags, pOptDebugBitcode, ppResult); }

vtable :: (obj: *IDxcValidator2) -> *IDxcValidator2_VTable { return obj.vtable; }


/// \brief Interface to DXC container builder.
///
/// Use DxcCreateInstance with CLSID_DxcContainerBuilder to obtain an instance
/// of this.
IDxcContainerBuilder :: struct {
    #as using,except(vtable) iunknown: IUnknown;

    #overlay (iunknown) vtable: *IDxcContainerBuilder_VTable; // Overlay parent's vtable with IDxcContainerBuilder’s vtable
}
IDxcContainerBuilder_VTable :: struct #type_info_none {
    using vtable:       IUnknown_VTable;
    Load:               #type (this: *IDxcContainerBuilder, pDxilContainerHeader: *IDxcBlob) -> HRESULT #cpp_method;
    AddPart:            #type (this: *IDxcContainerBuilder, fourCC: u32, pSource: *IDxcBlob) -> HRESULT #cpp_method;
    RemovePart:         #type (this: *IDxcContainerBuilder, fourCC: u32) -> HRESULT #cpp_method;
    SerializeContainer: #type (this: *IDxcContainerBuilder, ppResult: **IDxcOperationResult) -> HRESULT #cpp_method;
}
IDxcContainerBuilder_Load :: inline (this: *IDxcContainerBuilder, pDxilContainerHeader: *IDxcBlob) -> HRESULT { return this.vtable.Load(this, pDxilContainerHeader); }

IDxcContainerBuilder_AddPart :: inline (this: *IDxcContainerBuilder, fourCC: u32, pSource: *IDxcBlob) -> HRESULT { return this.vtable.AddPart(this, fourCC, pSource); }

IDxcContainerBuilder_RemovePart :: inline (this: *IDxcContainerBuilder, fourCC: u32) -> HRESULT { return this.vtable.RemovePart(this, fourCC); }

IDxcContainerBuilder_SerializeContainer :: inline (this: *IDxcContainerBuilder, ppResult: **IDxcOperationResult) -> HRESULT { return this.vtable.SerializeContainer(this, ppResult); }

vtable :: (obj: *IDxcContainerBuilder) -> *IDxcContainerBuilder_VTable { return obj.vtable; }


/// \brief Interface to DxcAssembler.
///
/// Use DxcCreateInstance with CLSID_DxcAssembler to obtain an instance of this.
IDxcAssembler :: struct {
    #as using,except(vtable) iunknown: IUnknown;

    #overlay (iunknown) vtable: *IDxcAssembler_VTable; // Overlay parent's vtable with IDxcAssembler’s vtable
}
IDxcAssembler_VTable :: struct #type_info_none {
    using vtable:        IUnknown_VTable;
    AssembleToContainer: #type (this: *IDxcAssembler, pShader: *IDxcBlob, ppResult: **IDxcOperationResult) -> HRESULT #cpp_method;
}
IDxcAssembler_AssembleToContainer :: inline (this: *IDxcAssembler, pShader: *IDxcBlob, ppResult: **IDxcOperationResult) -> HRESULT { return this.vtable.AssembleToContainer(this, pShader, ppResult); }

vtable :: (obj: *IDxcAssembler) -> *IDxcAssembler_VTable { return obj.vtable; }


/// \brief Interface to DxcContainerReflection.
///
/// Use DxcCreateInstance with CLSID_DxcContainerReflection to obtain an
/// instance of this.
IDxcContainerReflection :: struct {
    #as using,except(vtable) iunknown: IUnknown;

    #overlay (iunknown) vtable: *IDxcContainerReflection_VTable; // Overlay parent's vtable with IDxcContainerReflection’s vtable
}
IDxcContainerReflection_VTable :: struct #type_info_none {
    using vtable:      IUnknown_VTable;
    Load:              #type (this: *IDxcContainerReflection, pContainer: *IDxcBlob) -> HRESULT #cpp_method;
    GetPartCount:      #type (this: *IDxcContainerReflection, pResult: *u32) -> HRESULT #cpp_method;
    GetPartKind:       #type (this: *IDxcContainerReflection, idx: u32, pResult: *u32) -> HRESULT #cpp_method;
    GetPartContent:    #type (this: *IDxcContainerReflection, idx: u32, ppResult: **IDxcBlob) -> HRESULT #cpp_method;
    FindFirstPartKind: #type (this: *IDxcContainerReflection, kind: u32, pResult: *u32) -> HRESULT #cpp_method;
    GetPartReflection: #type (this: *IDxcContainerReflection, idx: u32, iid: *IID, ppvObject: **void) -> HRESULT #cpp_method;
}
IDxcContainerReflection_Load :: inline (this: *IDxcContainerReflection, pContainer: *IDxcBlob) -> HRESULT { return this.vtable.Load(this, pContainer); }

IDxcContainerReflection_GetPartCount :: inline (this: *IDxcContainerReflection, pResult: *u32) -> HRESULT { return this.vtable.GetPartCount(this, pResult); }

IDxcContainerReflection_GetPartKind :: inline (this: *IDxcContainerReflection, idx: u32, pResult: *u32) -> HRESULT { return this.vtable.GetPartKind(this, idx, pResult); }

IDxcContainerReflection_GetPartContent :: inline (this: *IDxcContainerReflection, idx: u32, ppResult: **IDxcBlob) -> HRESULT { return this.vtable.GetPartContent(this, idx, ppResult); }

IDxcContainerReflection_FindFirstPartKind :: inline (this: *IDxcContainerReflection, kind: u32, pResult: *u32) -> HRESULT { return this.vtable.FindFirstPartKind(this, kind, pResult); }

IDxcContainerReflection_GetPartReflection :: inline (this: *IDxcContainerReflection, idx: u32, iid: *IID, ppvObject: **void) -> HRESULT { return this.vtable.GetPartReflection(this, idx, iid, ppvObject); }

vtable :: (obj: *IDxcContainerReflection) -> *IDxcContainerReflection_VTable { return obj.vtable; }


/// \brief An optimizer pass.
///
/// Instances of this can be obtained via IDxcOptimizer::GetAvailablePass.
IDxcOptimizerPass :: struct {
    #as using,except(vtable) iunknown: IUnknown;

    #overlay (iunknown) vtable: *IDxcOptimizerPass_VTable; // Overlay parent's vtable with IDxcOptimizerPass’s vtable
}
IDxcOptimizerPass_VTable :: struct #type_info_none {
    using vtable:            IUnknown_VTable;
    GetOptionName:           #type (this: *IDxcOptimizerPass, ppResult: **s16) -> HRESULT #cpp_method;
    GetDescription:          #type (this: *IDxcOptimizerPass, ppResult: **s16) -> HRESULT #cpp_method;
    GetOptionArgCount:       #type (this: *IDxcOptimizerPass, pCount: *u32) -> HRESULT #cpp_method;
    GetOptionArgName:        #type (this: *IDxcOptimizerPass, argIndex: u32, ppResult: **s16) -> HRESULT #cpp_method;
    GetOptionArgDescription: #type (this: *IDxcOptimizerPass, argIndex: u32, ppResult: **s16) -> HRESULT #cpp_method;
}
IDxcOptimizerPass_GetOptionName :: inline (this: *IDxcOptimizerPass, ppResult: **s16) -> HRESULT { return this.vtable.GetOptionName(this, ppResult); }

IDxcOptimizerPass_GetDescription :: inline (this: *IDxcOptimizerPass, ppResult: **s16) -> HRESULT { return this.vtable.GetDescription(this, ppResult); }
IDxcOptimizerPass_GetOptionArgCount :: inline (this: *IDxcOptimizerPass, pCount: *u32) -> HRESULT { return this.vtable.GetOptionArgCount(this, pCount); }

IDxcOptimizerPass_GetOptionArgName :: inline (this: *IDxcOptimizerPass, argIndex: u32, ppResult: **s16) -> HRESULT { return this.vtable.GetOptionArgName(this, argIndex, ppResult); }

IDxcOptimizerPass_GetOptionArgDescription :: inline (this: *IDxcOptimizerPass, argIndex: u32, ppResult: **s16) -> HRESULT { return this.vtable.GetOptionArgDescription(this, argIndex, ppResult); }

vtable :: (obj: *IDxcOptimizerPass) -> *IDxcOptimizerPass_VTable { return obj.vtable; }


/// \brief Interface to DxcOptimizer.
///
/// Use DxcCreateInstance with CLSID_DxcOptimizer to obtain an instance of this.
IDxcOptimizer :: struct {
    #as using,except(vtable) iunknown: IUnknown;

    #overlay (iunknown) vtable: *IDxcOptimizer_VTable; // Overlay parent's vtable with IDxcOptimizer’s vtable
}
IDxcOptimizer_VTable :: struct #type_info_none {
    using vtable:          IUnknown_VTable;
    GetAvailablePassCount: #type (this: *IDxcOptimizer, pCount: *u32) -> HRESULT #cpp_method;
    GetAvailablePass:      #type (this: *IDxcOptimizer, index: u32, ppResult: **IDxcOptimizerPass) -> HRESULT #cpp_method;
    RunOptimizer:          #type (this: *IDxcOptimizer, pBlob: *IDxcBlob, ppOptions: **s16, optionCount: u32, pOutputModule: **IDxcBlob, ppOutputText: **IDxcBlobEncoding) -> HRESULT #cpp_method;
}
IDxcOptimizer_GetAvailablePassCount :: inline (this: *IDxcOptimizer, pCount: *u32) -> HRESULT { return this.vtable.GetAvailablePassCount(this, pCount); }

IDxcOptimizer_GetAvailablePass :: inline (this: *IDxcOptimizer, index: u32, ppResult: **IDxcOptimizerPass) -> HRESULT { return this.vtable.GetAvailablePass(this, index, ppResult); }

IDxcOptimizer_RunOptimizer :: inline (this: *IDxcOptimizer, pBlob: *IDxcBlob, ppOptions: **s16, optionCount: u32, pOutputModule: **IDxcBlob, ppOutputText: **IDxcBlobEncoding) -> HRESULT { return this.vtable.RunOptimizer(this, pBlob, ppOptions, optionCount, pOutputModule, ppOutputText); }

vtable :: (obj: *IDxcOptimizer) -> *IDxcOptimizer_VTable { return obj.vtable; }


DxcVersionInfoFlags_None: u32 : 0;
DxcVersionInfoFlags_Debug: u32 : 1; // Matches VS_FF_DEBUG
DxcVersionInfoFlags_Internal: u32 : 2;

/// \brief PDB Version information.
///
/// Use IDxcPdbUtils2::GetVersionInfo to obtain an instance of this.
IDxcVersionInfo :: struct {
    #as using,except(vtable) iunknown: IUnknown;

    #overlay (iunknown) vtable: *IDxcVersionInfo_VTable; // Overlay parent's vtable with IDxcVersionInfo’s vtable
}
IDxcVersionInfo_VTable :: struct #type_info_none {
    using vtable: IUnknown_VTable;
    GetVersion:   #type (this: *IDxcVersionInfo, pMajor: *u32, pMinor: *u32) -> HRESULT #cpp_method;
    GetFlags:     #type (this: *IDxcVersionInfo, pFlags: *u32) -> HRESULT #cpp_method;
}
IDxcVersionInfo_GetVersion :: inline (this: *IDxcVersionInfo, pMajor: *u32, pMinor: *u32) -> HRESULT { return this.vtable.GetVersion(this, pMajor, pMinor); }

IDxcVersionInfo_GetFlags :: inline (this: *IDxcVersionInfo, pFlags: *u32) -> HRESULT { return this.vtable.GetFlags(this, pFlags); }

vtable :: (obj: *IDxcVersionInfo) -> *IDxcVersionInfo_VTable { return obj.vtable; }


/// \brief PDB Version Information.
///
/// Use IDxcPdbUtils2::GetVersionInfo to obtain a IDxcVersionInfo interface, and
/// then use QueryInterface to obtain an instance of this interface from it.
IDxcVersionInfo2 :: struct {
    #as using,except(vtable) idxcversioninfo: IDxcVersionInfo;

    #overlay (idxcversioninfo) vtable: *IDxcVersionInfo2_VTable; // Overlay parent's vtable with IDxcVersionInfo2’s vtable
}
IDxcVersionInfo2_VTable :: struct #type_info_none {
    using,except(vtable) vtable:        IDxcVersionInfo_VTable;
    GetCommitInfo: #type (this: *IDxcVersionInfo2, pCommitCount: *u32, pCommitHash: **u8) -> HRESULT #cpp_method;
}
IDxcVersionInfo2_GetCommitInfo :: inline (this: *IDxcVersionInfo2, pCommitCount: *u32, pCommitHash: **u8) -> HRESULT { return this.vtable.GetCommitInfo(this, pCommitCount, pCommitHash); }

vtable :: (obj: *IDxcVersionInfo2) -> *IDxcVersionInfo2_VTable { return obj.vtable; }


/// \brief PDB Version Information.
///
/// Use IDxcPdbUtils2::GetVersionInfo to obtain a IDxcVersionInfo interface, and
/// then use QueryInterface to obtain an instance of this interface from it.
IDxcVersionInfo3 :: struct {
    #as using,except(vtable) iunknown: IUnknown;

    #overlay (iunknown) vtable: *IDxcVersionInfo3_VTable; // Overlay parent's vtable with IDxcVersionInfo3’s vtable
}
IDxcVersionInfo3_VTable :: struct #type_info_none {
    using vtable:           IUnknown_VTable;
    GetCustomVersionString: #type (this: *IDxcVersionInfo3, pVersionString: **u8) -> HRESULT #cpp_method;
}
IDxcVersionInfo3_GetCustomVersionString :: inline (this: *IDxcVersionInfo3, pVersionString: **u8) -> HRESULT { return this.vtable.GetCustomVersionString(this, pVersionString); }

vtable :: (obj: *IDxcVersionInfo3) -> *IDxcVersionInfo3_VTable { return obj.vtable; }


DxcArgPair :: struct {
    pName:  *s16;
    pValue: *s16;
}

/// \deprecated Please use IDxcPdbUtils2 instead.
IDxcPdbUtils :: struct {
    #as using,except(vtable) iunknown: IUnknown;

    #overlay (iunknown) vtable: *IDxcPdbUtils_VTable; // Overlay parent's vtable with IDxcPdbUtils’s vtable
}
IDxcPdbUtils_VTable :: struct #type_info_none {
    using vtable:          IUnknown_VTable;
    Load:                  #type (this: *IDxcPdbUtils, pPdbOrDxil: *IDxcBlob) -> HRESULT #cpp_method;
    GetSourceCount:        #type (this: *IDxcPdbUtils, pCount: *u32) -> HRESULT #cpp_method;
    GetSource:             #type (this: *IDxcPdbUtils, uIndex: u32, ppResult: **IDxcBlobEncoding) -> HRESULT #cpp_method;
    GetSourceName:         #type (this: *IDxcPdbUtils, uIndex: u32, pResult: *BSTR) -> HRESULT #cpp_method;
    GetFlagCount:          #type (this: *IDxcPdbUtils, pCount: *u32) -> HRESULT #cpp_method;
    GetFlag:               #type (this: *IDxcPdbUtils, uIndex: u32, pResult: *BSTR) -> HRESULT #cpp_method;
    GetArgCount:           #type (this: *IDxcPdbUtils, pCount: *u32) -> HRESULT #cpp_method;
    GetArg:                #type (this: *IDxcPdbUtils, uIndex: u32, pResult: *BSTR) -> HRESULT #cpp_method;
    GetArgPairCount:       #type (this: *IDxcPdbUtils, pCount: *u32) -> HRESULT #cpp_method;
    GetArgPair:            #type (this: *IDxcPdbUtils, uIndex: u32, pName: *BSTR, pValue: *BSTR) -> HRESULT #cpp_method;
    GetDefineCount:        #type (this: *IDxcPdbUtils, pCount: *u32) -> HRESULT #cpp_method;
    GetDefine:             #type (this: *IDxcPdbUtils, uIndex: u32, pResult: *BSTR) -> HRESULT #cpp_method;
    GetTargetProfile:      #type (this: *IDxcPdbUtils, pResult: *BSTR) -> HRESULT #cpp_method;
    GetEntryPoint:         #type (this: *IDxcPdbUtils, pResult: *BSTR) -> HRESULT #cpp_method;
    GetMainFileName:       #type (this: *IDxcPdbUtils, pResult: *BSTR) -> HRESULT #cpp_method;
    GetHash:               #type (this: *IDxcPdbUtils, ppResult: **IDxcBlob) -> HRESULT #cpp_method;
    GetName:               #type (this: *IDxcPdbUtils, pResult: *BSTR) -> HRESULT #cpp_method;
    IsFullPDB:             #type (this: *IDxcPdbUtils) -> BOOL #cpp_method;
    GetFullPDB:            #type (this: *IDxcPdbUtils, ppFullPDB: **IDxcBlob) -> HRESULT #cpp_method;
    GetVersionInfo:        #type (this: *IDxcPdbUtils, ppVersionInfo: **IDxcVersionInfo) -> HRESULT #cpp_method;
    SetCompiler:           #type (this: *IDxcPdbUtils, pCompiler: *IDxcCompiler3) -> HRESULT #cpp_method;
    CompileForFullPDB:     #type (this: *IDxcPdbUtils, ppResult: **IDxcResult) -> HRESULT #cpp_method;
    OverrideArgs:          #type (this: *IDxcPdbUtils, pArgPairs: *DxcArgPair, uNumArgPairs: u32) -> HRESULT #cpp_method;
    OverrideRootSignature: #type (this: *IDxcPdbUtils, pRootSignature: *s16) -> HRESULT #cpp_method;
}
IDxcPdbUtils_Load :: inline (this: *IDxcPdbUtils, pPdbOrDxil: *IDxcBlob) -> HRESULT { return this.vtable.Load(this, pPdbOrDxil); }

IDxcPdbUtils_GetSourceCount :: inline (this: *IDxcPdbUtils, pCount: *u32) -> HRESULT { return this.vtable.GetSourceCount(this, pCount); }

IDxcPdbUtils_GetSource :: inline (this: *IDxcPdbUtils, uIndex: u32, ppResult: **IDxcBlobEncoding) -> HRESULT { return this.vtable.GetSource(this, uIndex, ppResult); }

IDxcPdbUtils_GetSourceName :: inline (this: *IDxcPdbUtils, uIndex: u32, pResult: *BSTR) -> HRESULT { return this.vtable.GetSourceName(this, uIndex, pResult); }

IDxcPdbUtils_GetFlagCount :: inline (this: *IDxcPdbUtils, pCount: *u32) -> HRESULT { return this.vtable.GetFlagCount(this, pCount); }

IDxcPdbUtils_GetFlag :: inline (this: *IDxcPdbUtils, uIndex: u32, pResult: *BSTR) -> HRESULT { return this.vtable.GetFlag(this, uIndex, pResult); }

IDxcPdbUtils_GetArgCount :: inline (this: *IDxcPdbUtils, pCount: *u32) -> HRESULT { return this.vtable.GetArgCount(this, pCount); }
IDxcPdbUtils_GetArg :: inline (this: *IDxcPdbUtils, uIndex: u32, pResult: *BSTR) -> HRESULT { return this.vtable.GetArg(this, uIndex, pResult); }

IDxcPdbUtils_GetArgPairCount :: inline (this: *IDxcPdbUtils, pCount: *u32) -> HRESULT { return this.vtable.GetArgPairCount(this, pCount); }

IDxcPdbUtils_GetArgPair :: inline (this: *IDxcPdbUtils, uIndex: u32, pName: *BSTR, pValue: *BSTR) -> HRESULT { return this.vtable.GetArgPair(this, uIndex, pName, pValue); }

IDxcPdbUtils_GetDefineCount :: inline (this: *IDxcPdbUtils, pCount: *u32) -> HRESULT { return this.vtable.GetDefineCount(this, pCount); }

IDxcPdbUtils_GetDefine :: inline (this: *IDxcPdbUtils, uIndex: u32, pResult: *BSTR) -> HRESULT { return this.vtable.GetDefine(this, uIndex, pResult); }

IDxcPdbUtils_GetTargetProfile :: inline (this: *IDxcPdbUtils, pResult: *BSTR) -> HRESULT { return this.vtable.GetTargetProfile(this, pResult); }

IDxcPdbUtils_GetEntryPoint :: inline (this: *IDxcPdbUtils, pResult: *BSTR) -> HRESULT { return this.vtable.GetEntryPoint(this, pResult); }

IDxcPdbUtils_GetMainFileName :: inline (this: *IDxcPdbUtils, pResult: *BSTR) -> HRESULT { return this.vtable.GetMainFileName(this, pResult); }

IDxcPdbUtils_GetHash :: inline (this: *IDxcPdbUtils, ppResult: **IDxcBlob) -> HRESULT { return this.vtable.GetHash(this, ppResult); }

IDxcPdbUtils_GetName :: inline (this: *IDxcPdbUtils, pResult: *BSTR) -> HRESULT { return this.vtable.GetName(this, pResult); }

IDxcPdbUtils_IsFullPDB :: inline (this: *IDxcPdbUtils) -> BOOL { return this.vtable.IsFullPDB(this); }

IDxcPdbUtils_GetFullPDB :: inline (this: *IDxcPdbUtils, ppFullPDB: **IDxcBlob) -> HRESULT { return this.vtable.GetFullPDB(this, ppFullPDB); }

IDxcPdbUtils_GetVersionInfo :: inline (this: *IDxcPdbUtils, ppVersionInfo: **IDxcVersionInfo) -> HRESULT { return this.vtable.GetVersionInfo(this, ppVersionInfo); }

IDxcPdbUtils_SetCompiler :: inline (this: *IDxcPdbUtils, pCompiler: *IDxcCompiler3) -> HRESULT { return this.vtable.SetCompiler(this, pCompiler); }

IDxcPdbUtils_CompileForFullPDB :: inline (this: *IDxcPdbUtils, ppResult: **IDxcResult) -> HRESULT { return this.vtable.CompileForFullPDB(this, ppResult); }
IDxcPdbUtils_OverrideArgs :: inline (this: *IDxcPdbUtils, pArgPairs: *DxcArgPair, uNumArgPairs: u32) -> HRESULT { return this.vtable.OverrideArgs(this, pArgPairs, uNumArgPairs); }

IDxcPdbUtils_OverrideRootSignature :: inline (this: *IDxcPdbUtils, pRootSignature: *s16) -> HRESULT { return this.vtable.OverrideRootSignature(this, pRootSignature); }

vtable :: (obj: *IDxcPdbUtils) -> *IDxcPdbUtils_VTable { return obj.vtable; }


/// \brief DxcPdbUtils interface.
///
/// Use DxcCreateInstance with CLSID_DxcPdbUtils to create an instance of this.
IDxcPdbUtils2 :: struct {
    #as using,except(vtable) iunknown: IUnknown;

    #overlay (iunknown) vtable: *IDxcPdbUtils2_VTable; // Overlay parent's vtable with IDxcPdbUtils2’s vtable
}
IDxcPdbUtils2_VTable :: struct #type_info_none {
    using vtable:           IUnknown_VTable;
    Load:                   #type (this: *IDxcPdbUtils2, pPdbOrDxil: *IDxcBlob) -> HRESULT #cpp_method;
    GetSourceCount:         #type (this: *IDxcPdbUtils2, pCount: *u32) -> HRESULT #cpp_method;
    GetSource:              #type (this: *IDxcPdbUtils2, uIndex: u32, ppResult: **IDxcBlobEncoding) -> HRESULT #cpp_method;
    GetSourceName:          #type (this: *IDxcPdbUtils2, uIndex: u32, ppResult: **IDxcBlobWide) -> HRESULT #cpp_method;
    GetLibraryPDBCount:     #type (this: *IDxcPdbUtils2, pCount: *u32) -> HRESULT #cpp_method;
    GetLibraryPDB:          #type (this: *IDxcPdbUtils2, uIndex: u32, ppOutPdbUtils: **IDxcPdbUtils2, ppLibraryName: **IDxcBlobWide) -> HRESULT #cpp_method;
    GetFlagCount:           #type (this: *IDxcPdbUtils2, pCount: *u32) -> HRESULT #cpp_method;
    GetFlag:                #type (this: *IDxcPdbUtils2, uIndex: u32, ppResult: **IDxcBlobWide) -> HRESULT #cpp_method;
    GetArgCount:            #type (this: *IDxcPdbUtils2, pCount: *u32) -> HRESULT #cpp_method;
    GetArg:                 #type (this: *IDxcPdbUtils2, uIndex: u32, ppResult: **IDxcBlobWide) -> HRESULT #cpp_method;
    GetArgPairCount:        #type (this: *IDxcPdbUtils2, pCount: *u32) -> HRESULT #cpp_method;
    GetArgPair:             #type (this: *IDxcPdbUtils2, uIndex: u32, ppName: **IDxcBlobWide, ppValue: **IDxcBlobWide) -> HRESULT #cpp_method;
    GetDefineCount:         #type (this: *IDxcPdbUtils2, pCount: *u32) -> HRESULT #cpp_method;
    GetDefine:              #type (this: *IDxcPdbUtils2, uIndex: u32, ppResult: **IDxcBlobWide) -> HRESULT #cpp_method;
    GetTargetProfile:       #type (this: *IDxcPdbUtils2, ppResult: **IDxcBlobWide) -> HRESULT #cpp_method;
    GetEntryPoint:          #type (this: *IDxcPdbUtils2, ppResult: **IDxcBlobWide) -> HRESULT #cpp_method;
    GetMainFileName:        #type (this: *IDxcPdbUtils2, ppResult: **IDxcBlobWide) -> HRESULT #cpp_method;
    GetHash:                #type (this: *IDxcPdbUtils2, ppResult: **IDxcBlob) -> HRESULT #cpp_method;
    GetName:                #type (this: *IDxcPdbUtils2, ppResult: **IDxcBlobWide) -> HRESULT #cpp_method;
    GetVersionInfo:         #type (this: *IDxcPdbUtils2, ppVersionInfo: **IDxcVersionInfo) -> HRESULT #cpp_method;
    GetCustomToolchainID:   #type (this: *IDxcPdbUtils2, pID: *u32) -> HRESULT #cpp_method;
    GetCustomToolchainData: #type (this: *IDxcPdbUtils2, ppBlob: **IDxcBlob) -> HRESULT #cpp_method;
    GetWholeDxil:           #type (this: *IDxcPdbUtils2, ppResult: **IDxcBlob) -> HRESULT #cpp_method;
    IsFullPDB:              #type (this: *IDxcPdbUtils2) -> BOOL #cpp_method;
    IsPDBRef:               #type (this: *IDxcPdbUtils2) -> BOOL #cpp_method;
}
IDxcPdbUtils2_Load :: inline (this: *IDxcPdbUtils2, pPdbOrDxil: *IDxcBlob) -> HRESULT { return this.vtable.Load(this, pPdbOrDxil); }

IDxcPdbUtils2_GetSourceCount :: inline (this: *IDxcPdbUtils2, pCount: *u32) -> HRESULT { return this.vtable.GetSourceCount(this, pCount); }

IDxcPdbUtils2_GetSource :: inline (this: *IDxcPdbUtils2, uIndex: u32, ppResult: **IDxcBlobEncoding) -> HRESULT { return this.vtable.GetSource(this, uIndex, ppResult); }

IDxcPdbUtils2_GetSourceName :: inline (this: *IDxcPdbUtils2, uIndex: u32, ppResult: **IDxcBlobWide) -> HRESULT { return this.vtable.GetSourceName(this, uIndex, ppResult); }

IDxcPdbUtils2_GetLibraryPDBCount :: inline (this: *IDxcPdbUtils2, pCount: *u32) -> HRESULT { return this.vtable.GetLibraryPDBCount(this, pCount); }
IDxcPdbUtils2_GetLibraryPDB :: inline (this: *IDxcPdbUtils2, uIndex: u32, ppOutPdbUtils: **IDxcPdbUtils2, ppLibraryName: **IDxcBlobWide) -> HRESULT { return this.vtable.GetLibraryPDB(this, uIndex, ppOutPdbUtils, ppLibraryName); }

IDxcPdbUtils2_GetFlagCount :: inline (this: *IDxcPdbUtils2, pCount: *u32) -> HRESULT { return this.vtable.GetFlagCount(this, pCount); }

IDxcPdbUtils2_GetFlag :: inline (this: *IDxcPdbUtils2, uIndex: u32, ppResult: **IDxcBlobWide) -> HRESULT { return this.vtable.GetFlag(this, uIndex, ppResult); }

IDxcPdbUtils2_GetArgCount :: inline (this: *IDxcPdbUtils2, pCount: *u32) -> HRESULT { return this.vtable.GetArgCount(this, pCount); }

IDxcPdbUtils2_GetArg :: inline (this: *IDxcPdbUtils2, uIndex: u32, ppResult: **IDxcBlobWide) -> HRESULT { return this.vtable.GetArg(this, uIndex, ppResult); }

IDxcPdbUtils2_GetArgPairCount :: inline (this: *IDxcPdbUtils2, pCount: *u32) -> HRESULT { return this.vtable.GetArgPairCount(this, pCount); }
IDxcPdbUtils2_GetArgPair :: inline (this: *IDxcPdbUtils2, uIndex: u32, ppName: **IDxcBlobWide, ppValue: **IDxcBlobWide) -> HRESULT { return this.vtable.GetArgPair(this, uIndex, ppName, ppValue); }

IDxcPdbUtils2_GetDefineCount :: inline (this: *IDxcPdbUtils2, pCount: *u32) -> HRESULT { return this.vtable.GetDefineCount(this, pCount); }

IDxcPdbUtils2_GetDefine :: inline (this: *IDxcPdbUtils2, uIndex: u32, ppResult: **IDxcBlobWide) -> HRESULT { return this.vtable.GetDefine(this, uIndex, ppResult); }

IDxcPdbUtils2_GetTargetProfile :: inline (this: *IDxcPdbUtils2, ppResult: **IDxcBlobWide) -> HRESULT { return this.vtable.GetTargetProfile(this, ppResult); }

IDxcPdbUtils2_GetEntryPoint :: inline (this: *IDxcPdbUtils2, ppResult: **IDxcBlobWide) -> HRESULT { return this.vtable.GetEntryPoint(this, ppResult); }

IDxcPdbUtils2_GetMainFileName :: inline (this: *IDxcPdbUtils2, ppResult: **IDxcBlobWide) -> HRESULT { return this.vtable.GetMainFileName(this, ppResult); }

IDxcPdbUtils2_GetHash :: inline (this: *IDxcPdbUtils2, ppResult: **IDxcBlob) -> HRESULT { return this.vtable.GetHash(this, ppResult); }

IDxcPdbUtils2_GetName :: inline (this: *IDxcPdbUtils2, ppResult: **IDxcBlobWide) -> HRESULT { return this.vtable.GetName(this, ppResult); }

IDxcPdbUtils2_GetVersionInfo :: inline (this: *IDxcPdbUtils2, ppVersionInfo: **IDxcVersionInfo) -> HRESULT { return this.vtable.GetVersionInfo(this, ppVersionInfo); }

IDxcPdbUtils2_GetCustomToolchainID :: inline (this: *IDxcPdbUtils2, pID: *u32) -> HRESULT { return this.vtable.GetCustomToolchainID(this, pID); }

IDxcPdbUtils2_GetCustomToolchainData :: inline (this: *IDxcPdbUtils2, ppBlob: **IDxcBlob) -> HRESULT { return this.vtable.GetCustomToolchainData(this, ppBlob); }

IDxcPdbUtils2_GetWholeDxil :: inline (this: *IDxcPdbUtils2, ppResult: **IDxcBlob) -> HRESULT { return this.vtable.GetWholeDxil(this, ppResult); }

IDxcPdbUtils2_IsFullPDB :: inline (this: *IDxcPdbUtils2) -> BOOL { return this.vtable.IsFullPDB(this); }
IDxcPdbUtils2_IsPDBRef :: inline (this: *IDxcPdbUtils2) -> BOOL { return this.vtable.IsPDBRef(this); }

vtable :: (obj: *IDxcPdbUtils2) -> *IDxcPdbUtils2_VTable { return obj.vtable; }


#scope_file

#import "Basic"; // For assert


#run {
    {
        info := type_info(DxcShaderHash);
        for info.members {
            if it.name == {
                case "Flags";
                    assert(it.offset_in_bytes == 0, "DxcShaderHash.Flags has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "DxcShaderHash.Flags has unexpected size % instead of 4", it.type.runtime_size);
                case "HashDigest";
                    assert(it.offset_in_bytes == 4, "DxcShaderHash.HashDigest has unexpected offset % instead of 4", it.offset_in_bytes);
                    assert(it.type.runtime_size == 16, "DxcShaderHash.HashDigest has unexpected size % instead of 16", it.type.runtime_size);
            }
        }
        assert(size_of(DxcShaderHash) == 20, "DxcShaderHash has size % instead of 20", size_of(DxcShaderHash));
    }

    {
        info := type_info(IDxcBlob);
        for info.members {
            if it.name == {
                case "iunknown";
                    assert(it.offset_in_bytes == 0, "IDxcBlob.iunknown has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcBlob.iunknown has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcBlob.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcBlob.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcBlob) == 8, "IDxcBlob has size % instead of 8", size_of(IDxcBlob));
    }

    {
        info := type_info(IDxcBlobEncoding);
        for info.members {
            if it.name == {
                case "idxcblob";
                    assert(it.offset_in_bytes == 0, "IDxcBlobEncoding.idxcblob has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcBlobEncoding.idxcblob has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcBlobEncoding.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcBlobEncoding.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcBlobEncoding) == 8, "IDxcBlobEncoding has size % instead of 8", size_of(IDxcBlobEncoding));
    }

    {
        info := type_info(IDxcBlobWide);
        for info.members {
            if it.name == {
                case "idxcblobencoding";
                    assert(it.offset_in_bytes == 0, "IDxcBlobWide.idxcblobencoding has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcBlobWide.idxcblobencoding has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcBlobWide.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcBlobWide.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcBlobWide) == 8, "IDxcBlobWide has size % instead of 8", size_of(IDxcBlobWide));
    }

    {
        info := type_info(IDxcBlobUtf8);
        for info.members {
            if it.name == {
                case "idxcblobencoding";
                    assert(it.offset_in_bytes == 0, "IDxcBlobUtf8.idxcblobencoding has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcBlobUtf8.idxcblobencoding has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcBlobUtf8.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcBlobUtf8.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcBlobUtf8) == 8, "IDxcBlobUtf8 has size % instead of 8", size_of(IDxcBlobUtf8));
    }

    {
        info := type_info(IDxcIncludeHandler);
        for info.members {
            if it.name == {
                case "iunknown";
                    assert(it.offset_in_bytes == 0, "IDxcIncludeHandler.iunknown has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcIncludeHandler.iunknown has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcIncludeHandler.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcIncludeHandler.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcIncludeHandler) == 8, "IDxcIncludeHandler has size % instead of 8", size_of(IDxcIncludeHandler));
    }

    {
        info := type_info(DxcBuffer);
        for info.members {
            if it.name == {
                case "Ptr";
                    assert(it.offset_in_bytes == 0, "DxcBuffer.Ptr has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "DxcBuffer.Ptr has unexpected size % instead of 8", it.type.runtime_size);
                case "Size";
                    assert(it.offset_in_bytes == 8, "DxcBuffer.Size has unexpected offset % instead of 8", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "DxcBuffer.Size has unexpected size % instead of 8", it.type.runtime_size);
                case "Encoding";
                    assert(it.offset_in_bytes == 16, "DxcBuffer.Encoding has unexpected offset % instead of 16", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "DxcBuffer.Encoding has unexpected size % instead of 4", it.type.runtime_size);
            }
        }
        assert(size_of(DxcBuffer) == 24, "DxcBuffer has size % instead of 24", size_of(DxcBuffer));
    }

    {
        info := type_info(DxcDefine);
        for info.members {
            if it.name == {
                case "Name";
                    assert(it.offset_in_bytes == 0, "DxcDefine.Name has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "DxcDefine.Name has unexpected size % instead of 8", it.type.runtime_size);
                case "Value";
                    assert(it.offset_in_bytes == 8, "DxcDefine.Value has unexpected offset % instead of 8", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "DxcDefine.Value has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(DxcDefine) == 16, "DxcDefine has size % instead of 16", size_of(DxcDefine));
    }

    {
        info := type_info(IDxcCompilerArgs);
        for info.members {
            if it.name == {
                case "iunknown";
                    assert(it.offset_in_bytes == 0, "IDxcCompilerArgs.iunknown has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcCompilerArgs.iunknown has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcCompilerArgs.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcCompilerArgs.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcCompilerArgs) == 8, "IDxcCompilerArgs has size % instead of 8", size_of(IDxcCompilerArgs));
    }

    {
        info := type_info(IDxcLibrary);
        for info.members {
            if it.name == {
                case "iunknown";
                    assert(it.offset_in_bytes == 0, "IDxcLibrary.iunknown has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcLibrary.iunknown has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcLibrary.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcLibrary.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcLibrary) == 8, "IDxcLibrary has size % instead of 8", size_of(IDxcLibrary));
    }

    {
        info := type_info(IDxcOperationResult);
        for info.members {
            if it.name == {
                case "iunknown";
                    assert(it.offset_in_bytes == 0, "IDxcOperationResult.iunknown has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcOperationResult.iunknown has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcOperationResult.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcOperationResult.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcOperationResult) == 8, "IDxcOperationResult has size % instead of 8", size_of(IDxcOperationResult));
    }

    {
        info := type_info(IDxcCompiler);
        for info.members {
            if it.name == {
                case "iunknown";
                    assert(it.offset_in_bytes == 0, "IDxcCompiler.iunknown has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcCompiler.iunknown has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcCompiler.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcCompiler.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcCompiler) == 8, "IDxcCompiler has size % instead of 8", size_of(IDxcCompiler));
    }

    {
        info := type_info(IDxcCompiler2);
        for info.members {
            if it.name == {
                case "idxccompiler";
                    assert(it.offset_in_bytes == 0, "IDxcCompiler2.idxccompiler has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcCompiler2.idxccompiler has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcCompiler2.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcCompiler2.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcCompiler2) == 8, "IDxcCompiler2 has size % instead of 8", size_of(IDxcCompiler2));
    }

    {
        info := type_info(IDxcLinker);
        for info.members {
            if it.name == {
                case "iunknown";
                    assert(it.offset_in_bytes == 0, "IDxcLinker.iunknown has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcLinker.iunknown has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcLinker.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcLinker.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcLinker) == 8, "IDxcLinker has size % instead of 8", size_of(IDxcLinker));
    }

    {
        info := type_info(IDxcUtils);
        for info.members {
            if it.name == {
                case "iunknown";
                    assert(it.offset_in_bytes == 0, "IDxcUtils.iunknown has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcUtils.iunknown has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcUtils.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcUtils.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcUtils) == 8, "IDxcUtils has size % instead of 8", size_of(IDxcUtils));
    }

    {
        info := type_info(IDxcResult);
        for info.members {
            if it.name == {
                case "idxcoperationresult";
                    assert(it.offset_in_bytes == 0, "IDxcResult.idxcoperationresult has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcResult.idxcoperationresult has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcResult.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcResult.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcResult) == 8, "IDxcResult has size % instead of 8", size_of(IDxcResult));
    }

    {
        info := type_info(IDxcExtraOutputs);
        for info.members {
            if it.name == {
                case "iunknown";
                    assert(it.offset_in_bytes == 0, "IDxcExtraOutputs.iunknown has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcExtraOutputs.iunknown has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcExtraOutputs.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcExtraOutputs.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcExtraOutputs) == 8, "IDxcExtraOutputs has size % instead of 8", size_of(IDxcExtraOutputs));
    }

    {
        info := type_info(IDxcCompiler3);
        for info.members {
            if it.name == {
                case "iunknown";
                    assert(it.offset_in_bytes == 0, "IDxcCompiler3.iunknown has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcCompiler3.iunknown has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcCompiler3.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcCompiler3.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcCompiler3) == 8, "IDxcCompiler3 has size % instead of 8", size_of(IDxcCompiler3));
    }

    {
        info := type_info(IDxcValidator);
        for info.members {
            if it.name == {
                case "iunknown";
                    assert(it.offset_in_bytes == 0, "IDxcValidator.iunknown has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcValidator.iunknown has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcValidator.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcValidator.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcValidator) == 8, "IDxcValidator has size % instead of 8", size_of(IDxcValidator));
    }

    {
        info := type_info(IDxcValidator2);
        for info.members {
            if it.name == {
                case "idxcvalidator";
                    assert(it.offset_in_bytes == 0, "IDxcValidator2.idxcvalidator has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcValidator2.idxcvalidator has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcValidator2.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcValidator2.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcValidator2) == 8, "IDxcValidator2 has size % instead of 8", size_of(IDxcValidator2));
    }

    {
        info := type_info(IDxcContainerBuilder);
        for info.members {
            if it.name == {
                case "iunknown";
                    assert(it.offset_in_bytes == 0, "IDxcContainerBuilder.iunknown has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcContainerBuilder.iunknown has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcContainerBuilder.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcContainerBuilder.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcContainerBuilder) == 8, "IDxcContainerBuilder has size % instead of 8", size_of(IDxcContainerBuilder));
    }

    {
        info := type_info(IDxcAssembler);
        for info.members {
            if it.name == {
                case "iunknown";
                    assert(it.offset_in_bytes == 0, "IDxcAssembler.iunknown has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcAssembler.iunknown has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcAssembler.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcAssembler.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcAssembler) == 8, "IDxcAssembler has size % instead of 8", size_of(IDxcAssembler));
    }

    {
        info := type_info(IDxcContainerReflection);
        for info.members {
            if it.name == {
                case "iunknown";
                    assert(it.offset_in_bytes == 0, "IDxcContainerReflection.iunknown has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcContainerReflection.iunknown has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcContainerReflection.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcContainerReflection.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcContainerReflection) == 8, "IDxcContainerReflection has size % instead of 8", size_of(IDxcContainerReflection));
    }

    {
        info := type_info(IDxcOptimizerPass);
        for info.members {
            if it.name == {
                case "iunknown";
                    assert(it.offset_in_bytes == 0, "IDxcOptimizerPass.iunknown has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcOptimizerPass.iunknown has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcOptimizerPass.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcOptimizerPass.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcOptimizerPass) == 8, "IDxcOptimizerPass has size % instead of 8", size_of(IDxcOptimizerPass));
    }

    {
        info := type_info(IDxcOptimizer);
        for info.members {
            if it.name == {
                case "iunknown";
                    assert(it.offset_in_bytes == 0, "IDxcOptimizer.iunknown has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcOptimizer.iunknown has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcOptimizer.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcOptimizer.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcOptimizer) == 8, "IDxcOptimizer has size % instead of 8", size_of(IDxcOptimizer));
    }

    {
        info := type_info(IDxcVersionInfo);
        for info.members {
            if it.name == {
                case "iunknown";
                    assert(it.offset_in_bytes == 0, "IDxcVersionInfo.iunknown has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcVersionInfo.iunknown has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcVersionInfo.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcVersionInfo.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcVersionInfo) == 8, "IDxcVersionInfo has size % instead of 8", size_of(IDxcVersionInfo));
    }

    {
        info := type_info(IDxcVersionInfo2);
        for info.members {
            if it.name == {
                case "idxcversioninfo";
                    assert(it.offset_in_bytes == 0, "IDxcVersionInfo2.idxcversioninfo has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcVersionInfo2.idxcversioninfo has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcVersionInfo2.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcVersionInfo2.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcVersionInfo2) == 8, "IDxcVersionInfo2 has size % instead of 8", size_of(IDxcVersionInfo2));
    }

    {
        info := type_info(IDxcVersionInfo3);
        for info.members {
            if it.name == {
                case "iunknown";
                    assert(it.offset_in_bytes == 0, "IDxcVersionInfo3.iunknown has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcVersionInfo3.iunknown has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcVersionInfo3.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcVersionInfo3.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcVersionInfo3) == 8, "IDxcVersionInfo3 has size % instead of 8", size_of(IDxcVersionInfo3));
    }

    {
        info := type_info(DxcArgPair);
        for info.members {
            if it.name == {
                case "pName";
                    assert(it.offset_in_bytes == 0, "DxcArgPair.pName has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "DxcArgPair.pName has unexpected size % instead of 8", it.type.runtime_size);
                case "pValue";
                    assert(it.offset_in_bytes == 8, "DxcArgPair.pValue has unexpected offset % instead of 8", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "DxcArgPair.pValue has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(DxcArgPair) == 16, "DxcArgPair has size % instead of 16", size_of(DxcArgPair));
    }

    {
        info := type_info(IDxcPdbUtils);
        for info.members {
            if it.name == {
                case "iunknown";
                    assert(it.offset_in_bytes == 0, "IDxcPdbUtils.iunknown has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcPdbUtils.iunknown has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcPdbUtils.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcPdbUtils.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcPdbUtils) == 8, "IDxcPdbUtils has size % instead of 8", size_of(IDxcPdbUtils));
    }

    {
        info := type_info(IDxcPdbUtils2);
        for info.members {
            if it.name == {
                case "iunknown";
                    assert(it.offset_in_bytes == 0, "IDxcPdbUtils2.iunknown has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcPdbUtils2.iunknown has unexpected size % instead of 8", it.type.runtime_size);
                case "vtable";
                    assert(it.offset_in_bytes == 0, "IDxcPdbUtils2.vtable has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "IDxcPdbUtils2.vtable has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(IDxcPdbUtils2) == 8, "IDxcPdbUtils2 has size % instead of 8", size_of(IDxcPdbUtils2));
    }
}

#if OS == .WINDOWS {
    dxcompiler :: #library "lib/dxcompiler";
} else  {
    dxcompiler :: #library "lib/libdxcompiler";
}
