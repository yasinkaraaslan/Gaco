//
// DirectXShaderCompiler module. Currently windows and linux only, Android support is coming "soon"!
//
#module_parameters () (NINTENDO_SUPPORT := false);

dxc_get_version_string :: () -> string {
    compiler: *IDxcCompiler3;
    defer safe_release(compiler);

    CheckCom(DxcCreateInstance(*CLSID_DxcCompiler, *IDxcCompiler3_UID, xx *compiler));

    version_info: *IDxcVersionInfo;
    CheckCom(IUnknown_QueryInterface(compiler, *IDxcVersionInfo_UID, xx *version_info));
    defer  IUnknown_Release(version_info);

    major, minor: u32;
    CheckCom(IDxcVersionInfo_GetVersion(version_info, *major, *minor));

    // There are two additional version interfaces... "2" gives us the commit count and hash, not very useful.
    // "3" gives a "custom" string that is more useful, but the returned string has to be freed with CoTaskMemFree, gross.

    #if USE_WIN32 {
        ole32 :: #library,system "ole32";
        CoTaskMemFree :: (microsoft_is_not_good: *void) #foreign ole32;

        version_info3: *IDxcVersionInfo3;
        CheckCom(IUnknown_QueryInterface(compiler, *IDxcVersionInfo3_UID, xx *version_info3));
        defer  IUnknown_Release(version_info3);

        custom_string: *u8;
        CheckCom(IDxcVersionInfo3_GetCustomVersionString(version_info3, *custom_string));
        defer  CoTaskMemFree(custom_string);

        result := sprint("v%.% [%]", major, minor, to_string(custom_string));
    } else {
        result := sprint("v%.%", major, minor);
    }

    return result;
}

Shader_Type :: enum {
    Vertex;
    Fragment;
    Compute;
    Hull; // Also called Tessellation Control
    Domain; // Also called Tessellation Eval
    Mesh;
    Amplification;
    Library; // Used for raytracing pipelines
}

Dxc_Shader_Compiler_Args :: struct {
    shader_name:          string;
    shader_source:        string;
    shader_model_version: string;
    shader_type:          Shader_Type;
    entry_point:          string;
    defines:              [] string;
    extra_args:           [] string;
    add_debug_info:       bool;
    warnings_as_error:    bool;
    skip_optimization:    bool;

    spirv_target_env: string; // Set this to something like "vulkan1.3" or "vulkan1.1spirv1.4" to target SPIR-V
    spirv_generate_non_semanantic_debug_info := true;

    turn_off_validation:  bool;
}

DXC_Compile :: (args: Dxc_Shader_Compiler_Args) -> [..]u8 {
    target: string;
    if args.shader_type == {
        case .Vertex;            target = tprint("vs_%", args.shader_model_version);
        case .Fragment;          target = tprint("ps_%", args.shader_model_version);
        case .Compute;           target = tprint("cs_%", args.shader_model_version);
        case .Hull;              target = tprint("hs_%", args.shader_model_version);
        case .Domain;            target = tprint("ds_%", args.shader_model_version);
        case .Mesh;              target = tprint("ms_%", args.shader_model_version);
        case .Amplification;     target = tprint("as_%", args.shader_model_version);
        case .Library;           target = tprint("lib_%", args.shader_model_version);
        case; assert(false);
    }

    // The Utils and Compiler objects can be reused between compiles, and they are even thread safe.
    // However, it doesn't appear to make a big difference to overall compilation time so we do the simple thing.
    dxc_utils : *IDxcUtils;
    dxc_compiler : *IDxcCompiler3;
    defer safe_release(dxc_utils);
    defer safe_release(dxc_compiler);

    CheckCom(DxcCreateInstance(*CLSID_DxcUtils, *IDxcUtils_UID, xx *dxc_utils));
    CheckCom(DxcCreateInstance(*CLSID_DxcCompiler, *IDxcCompiler3_UID, xx *dxc_compiler));

    // shader compiler arguments
    arguments: [..] string;
    arguments.allocator = temp;
    array_add(*arguments, args.shader_name);
    array_add(*arguments, "-E");
    array_add(*arguments, args.entry_point);
    array_add(*arguments, "-T");
    array_add(*arguments, target);
    array_add(*arguments, "-HV 2021");

    if args.spirv_target_env {
        // See DirectXShaderCompiler/docs/SPIR-V.rst for more.

        array_add(*arguments, "-spirv");
        array_add(*arguments, "-fvk-use-dx-layout");
        array_add(*arguments, "-fvk-use-dx-position-w");
        array_add(*arguments, "-fvk-support-nonzero-base-instance");
        array_add(*arguments, tprint("-fspv-target-env=%", args.spirv_target_env));
        if args.add_debug_info {
            // Using fspv-debug will override -Zi and gives fine grained control over what is emitted.
            // -Zi implies all of these so for now we just use the same add_debug_info arg as for non spirv.
            /*
            array_add(*arguments, "-fspv-debug=file");
            array_add(*arguments, "-fspv-debug=source");
            array_add(*arguments, "-fspv-debug=line");
            array_add(*arguments, "-fspv-debug=tool");
            */

            if args.spirv_generate_non_semanantic_debug_info {
                // This overrules any other fspv-debug args (and also -Zi).
                array_add(*arguments, "-fspv-debug=vulkan-with-source");
            }
        }
    }

    if args.turn_off_validation {
        array_add(*arguments, "-Vd");
    }

    for args.defines {
        array_add(*arguments, "-D");
        array_add(*arguments, it);
    }

    for args.extra_args {
        array_add(*arguments, it);
    }

    if args.skip_optimization {
        array_add(*arguments, "-Od");           // Disable optimizations
    }
    if args.add_debug_info {
        array_add(*arguments, "-Zi");           // Enable debug information
        array_add(*arguments, "-Zss");          // Compute Shader Hash considering source information
        array_add(*arguments, "-Qembed_debug"); // Embed PDB in shader container (must be used with /Zi)
    }
    if args.warnings_as_error {
        array_add(*arguments, "-WX");           // Treat warnings as errors
    }

    // Dxc wants all its string arguments as wide strings.
    // Wide strings are 32 bits in Linux.
    // https://github.com/microsoft/DirectXShaderCompiler/issues/4742

    #if OS == .WINDOWS {
        arguments_wide: [..] *u16;
    }
    else #if OS == .LINUX {
        arguments_wide: [..] *u32;
    }

    arguments_wide.allocator = temp;

    for arguments {
        wide_string, success := utf8_to_wide(it,, temp);
        assert(success);
        array_add(*arguments_wide, wide_string);
    }

    handler : *IDxcIncludeHandler;
    CheckCom(IDxcUtils_CreateDefaultIncludeHandler(dxc_utils, *handler));
    defer safe_release(handler);

    shader_source_c_string := temp_c_string(args.shader_source);

    blob_encoding: *IDxcBlobEncoding;
    defer safe_release(blob_encoding);

    CheckCom(IDxcUtils_CreateBlobFromPinned(dxc_utils, shader_source_c_string, xx args.shader_source.count, cast(u32)CP_UTF8, *blob_encoding));

    shader_buffer : DxcBuffer;
    shader_buffer.Ptr      = IDxcBlob_GetBufferPointer(blob_encoding);
    shader_buffer.Size     = IDxcBlob_GetBufferSize(blob_encoding);
    shader_buffer.Encoding = 0;
    assert(shader_buffer.Ptr != null);
    assert(shader_buffer.Size > 0);

    dxc_result: *IDxcResult;
    defer safe_release(dxc_result);

    CheckCom(IDxcCompiler3_Compile(dxc_compiler, *shader_buffer, cast(**s16)arguments_wide.data, xx arguments_wide.count, handler, *IDxcResult_UID, xx *dxc_result));

    // Check the compiler status and printing out any errors.
    result: HRESULT;
    IDxcOperationResult_GetStatus(dxc_result, *result);
    if result != S_OK {
        error_blob: *IDxcBlobUtf8;
        defer safe_release(error_blob);

        IDxcResult_GetOutput(dxc_result, .DXC_OUT_ERRORS, *IDxcBlobUtf8_UID, xx *error_blob, null);

        if error_blob && IDxcBlobUtf8_GetStringLength(error_blob) > 0
        {
            error_string := to_string(IDxcBlobUtf8_GetStringPointer(error_blob));
            log_error("[DXC] Error while compiling shader: %\n", error_string);
        }
         empty :[..]u8;
         return empty;
    }
    binary_blog : *IDxcBlob;
    defer safe_release(binary_blog);

    CheckCom(IDxcOperationResult_GetResult(cast(*IDxcOperationResult)dxc_result, *binary_blog));

    binary_result: [..] u8;
    buffer_size := IDxcBlob_GetBufferSize(binary_blog);
    assert(buffer_size > 0);
    array_resize(*binary_result, xx buffer_size, false);
    memcpy(binary_result.data, IDxcBlob_GetBufferPointer(binary_blog), xx buffer_size);

    return binary_result;
}

DXC_Reflect :: (dxil: []u8) -> *ID3D12ShaderReflection, bool {
    utils: *IDxcUtils;
    CheckCom(DxcCreateInstance(*CLSID_DxcUtils, *IDxcUtils_UID, xx *utils));

    buffer: DxcBuffer;
    buffer.Ptr = dxil.data;
    buffer.Size = xx dxil.count;

    reflection: *ID3D12ShaderReflection;
    desc: D3D12_SHADER_DESC;

    result := IDxcUtils_CreateReflection(utils, *buffer, *uid(ID3D12ShaderReflection_UUID), xx *reflection);
    if FAILED(result)  return null, false;

    IUnknown_Release(utils);

    return reflection, true;
}

#if NINTENDO_SUPPORT {
    #load "nintendo/bindings.jai";
} else {
    #load "dxc_compiler_bindings.jai";
}

// @Incomplete: There are more CLSID's and UID's, these are just the ones we currently use.

CLSID_DxcCompiler :: GUID.{0x73E22D93, 0xE6CE, 0x47F3, .[0xB5, 0xBF, 0xF0, 0x66, 0x4F, 0x39, 0xC1, 0xB0]}; // 73E22D93-E6CE-47F3-B5BF-F0664F39C1B0
CLSID_DxcUtils    :: GUID.{0x6245D6AF, 0x66E0, 0x48FD, .[0x80, 0xB4, 0x4D, 0x27, 0x17, 0x96, 0x74, 0x8C]}; // 6245D6AF-66E0-48FD-80B4-4D271796748C
CLSID_DxcPdbUtils :: GUID.{0X54621DFB, 0XF2CE, 0X457E, .[0XAE, 0X8C, 0XEC, 0X35, 0X5F, 0XAE, 0XEC, 0X7C]}; // 54621dfb-f2ce-457e-ae8c-ec355faeec7c

// In windows headers the uuids are associated with interfaces via the CROSS_PLATFORM_UUIDOF macro. User code then
// uses the IID_PPV_ARGS macro to fill in the uuid when required. The macros achieve this with compiler specific
// stuff that we obviously don't have in jai. For now we just manually declare these literals.

IDxcCompiler3_UID :: GUID.{0x228B4687, 0x5A6A, 0x4730, .[0x90, 0x0C, 0x97, 0x02, 0xB2, 0x20, 0x3F, 0x54]}; // 228B4687-5A6A-4730-900C-9702B2203F54
IDxcUtils_UID     :: GUID.{0x4605C4CB, 0x2019, 0x492A, .[0xAD, 0xA4, 0x65, 0xF2, 0x0B, 0xB7, 0xD6, 0x7F]}; // 4605C4CB-2019-492A-ADA4-65F20BB7D67F
IDxcResult_UID    :: GUID.{0x58346CDA, 0xDDE7, 0x4497, .[0x94, 0x61, 0x6F, 0x87, 0xAF, 0x5E, 0x06, 0x59]}; // 58346CDA-DDE7-4497-9461-6F87AF5E0659
IDxcBlobUtf8_UID  :: GUID.{0x3DA636C9, 0xBA71, 0x4024, .[0xA3, 0x01, 0x30, 0xCB, 0xF1, 0x25, 0x30, 0x5B]}; // 3DA636C9-BA71-4024-A301-30CBF125305B

IDxcPdbUtils_UID     :: GUID.{0xE6C9647E, 0x9D6A, 0x4C3B, .[0xB9, 0x4C, 0x52, 0x4B, 0x5A, 0x6C, 0x34, 0x3D]}; // "E6C9647E-9D6A-4C3B-B94C-524B5A6C343D"
IDxcVersionInfo_UID  :: GUID.{0XB04F5B50, 0X2059, 0X4F12, .[0XA8, 0XFF, 0XA1, 0XE0, 0XCD, 0XE1, 0XCC, 0X7E]}; // b04f5b50-2059-4f12-a8ff-a1e0cde1cc7e
IDxcVersionInfo2_UID :: GUID.{0XFB6904C4, 0X42F0, 0X4B62, .[0X9C, 0X46, 0X98, 0X3A, 0XF7, 0XDA, 0X7C, 0X83]}; // fb6904c4-42f0-4b62-9c46-983af7da7c83
IDxcVersionInfo3_UID :: GUID.{0X5E13E843, 0X9D25, 0X473C, .[0X9A, 0XD2, 0X03, 0XB2, 0XD0, 0XB4, 0X4B, 0X1E]}; // 5e13e843-9d25-473c-9ad2-03b2d0b44b1e

#scope_module

IMalloc :: struct {};
IStream :: struct {};
BSTR :: struct {};

#if OS == .WINDOWS {
    #import "d3d12";
    #import "Windows";
    #import "Windows_Utf8";
}
else #if OS == .LINUX {
    SIZE_T :: u64;
    BOOL :: bool;
    HRESULT :: s32;
    IID :: GUID;
    GUID :: struct {
        Data1: u32;
        Data2: u16;
        Data3: u16;
        Data4: [8] u8;
    }

    S_OK : s32 : 0;
    CP_UTF8 : u32 : 65001;

    utf8_to_wide :: (s: string) -> *u32, bool {
        cursor := s;
        wide: [..]u32;

        result: Unicode_Result;
        while true {
            code:, result = utf8_next_character(*cursor);
            if result != .CONVERSION_OK
                break;
            array_add(*wide, code);
        }

        array_add(*wide, 0);
        success := result == .SOURCE_EXHAUSTED;
        return wide.data, success;
    }

    safe_release :: (obj: *IUnknown) {
        if obj then obj.vtable.Release(obj);
    }

    IUnknown :: struct {
        vtable: *IUnknown_VTable;
    }
    IUnknown_VTable :: struct {
        QueryInterface: (this: *IUnknown, riid: *IID, ppvObject: **void) -> HRESULT #cpp_method;
        AddRef: (this: *IUnknown) -> u32 #cpp_method;
        Release: (this: *IUnknown) -> u32 #cpp_method;
    }
    ID3D12ShaderReflection :: struct {};

    #import "Unicode";
}

#scope_file

USE_WIN32 :: true; // Won't be true for all non windows platforms, eg Android.

CheckCom :: (result: HRESULT, $call := #caller_code, loc := #caller_location) -> HRESULT #expand {
    #import "Compiler";

    // Convert caller code into the name of the procedure that produced the result. For times when you have stored the
    // result in a variable but still want to call this check proc you can pass the api call you made as the second
    // argument, eg CheckCom(my_hresult, DxcCreateInstance).
    CALL_STRING :: #run -> string {
        root := compiler_get_nodes(call);

        call_string := "Unknown";

        if root.kind == {
            case .PROCEDURE_CALL;
            proc_call  := cast(*Code_Procedure_Call) root;
            expression := proc_call.arguments_sorted[0];

            if expression.kind == .PROCEDURE_CALL {
                call := cast(*Code_Procedure_Call) expression;
                if call.procedure_expression.kind == .IDENT {
                    call_string = (cast(*Code_Ident) call.procedure_expression).name;
                }
            }

            case .IDENT;
            call_string = (cast(*Code_Ident) root).name;
        }

        return call_string;
    };

    // @Incomplete: Are we able to give better error info than just the HRESULT value?
    assert(result == S_OK, "'%' failed with error: %. (%:%)", CALL_STRING, result, loc.fully_pathed_filename, loc.line_number, loc = loc);

    return result;
}
