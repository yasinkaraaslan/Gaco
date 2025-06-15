#module_parameters (BACKEND := DEFAULT_BACKEND, DEBUG:=false) {
	Backend_Type :: enum #specified {
		Vulkan :: 0;
		D3D11 :: 1;
	};
	DEFAULT_BACKEND :: #run -> Backend_Type {
		#if OS == .WINDOWS return .D3D11;
		else #if OS == .LINUX | OS == .ANDROID return .Vulkan;
		else #if OS == .MACOS | OS == .IOS  #assert false, "Metal is not supported right now.";
	}

	//
	// Note that you have to add this to your main program to enable DEBUG while using the D3D11 backend:
	// #if OS == .WINDOWS {
	// 	D3D11 :: #import "d3d11"()(INCLUDE_DEBUG_BINDINGS=true);
	// }
	//
}
Shader_Type :: enum_flags u8 #specified {
	Unspecified :: 0;
	Vertex :: 0x1;
	Fragment :: 0x2;
	Compute :: 0x4;
};


// This is not a union since one hlsl file can output cs, vs and fs at the same time
Shader_Bytecode :: struct {
	vs: string;
	fs: string;
	cs: string;
}

Primitive_Type :: enum {
	Triangle_List;
	Triangle_Strip;
}


// We use HLSL naming here since we expect it to be used for
// both d3d11 and opengl backend.
Buffer_Type :: enum {
	Vertex;
	Index;
	Constant;
	Structured;
	RWStructured;
	Copy;
}

Sampler_Filtering :: enum {
	Linear;
	Nearest;
}

// @Rename
Sampler_Edge_Handling :: enum {
	Wrap :: 1;
	Mirror :: 2;
	Clamp :: 3;
	Border :: 4;
}

compile_shader :: (file_name: string, output_path: string, type: Shader_Type) -> bool {
	source, read_ok := read_entire_file(file_name, zero_terminated=true);
	defer free(source);
	if !read_ok return false;

	// SPIR-V or DXIL or something...
	bytecode, compile_ok := compile_shader_to_bytecode(source, type, path_filename(file_name));
	if !compile_ok return false;
	if type & .Vertex {
		write_ok := write_entire_file(join(output_path, VS_EXTENSION), bytecode.vs);
		if !write_ok return false;
		free(bytecode.vs);
	}

	if type & .Fragment {
		write_ok := write_entire_file(join(output_path, FS_EXTENSION), bytecode.fs);
		if !write_ok return false;
		free(bytecode.fs);
	}

	if type & .Compute {
		write_ok := write_entire_file(join(output_path, CS_EXTENSION), bytecode.cs);
		if !write_ok return false;
		free(bytecode.cs);
	}

	return true;
}

load_shader_bytecode :: (shader_file: string, type: Shader_Type) -> Shader_Bytecode {
	bytecode: Shader_Bytecode;
	ok := false;
	if type & .Vertex {
		file_name := join(shader_file, VS_EXTENSION);
		bytecode.vs, ok = read_entire_file(file_name);
		if !ok return .{};
	}

	if type & .Fragment {
		file_name := join(shader_file, FS_EXTENSION);
		bytecode.fs, ok = read_entire_file(file_name);
		if !ok return .{};
	}

	if type & .Compute {
		file_name := join(shader_file, CS_EXTENSION);
		bytecode.cs, ok = read_entire_file(file_name);
		if !ok return .{};
	}
	return bytecode;
}

create_texture_from_file :: (file_name: string) -> Texture {
	bytes, ok := read_entire_file(file_name);
	if !ok return .{};
	width, height, channels: s32;
	buffer := stbi_load_from_memory(bytes.data, cast(s32)bytes.count, *width, *height, *channels, 4);
	return create_texture(buffer, cast(u32)width, cast(u32)height, cast(u32)channels);
}

#if BACKEND == {
case .D3D11;
#load "backends/d3d11.jai";
case .Vulkan;
#load "backends/vulkan.jai";
}

#scope_module
VS_ENTRY_POINT :: "vertex_main";
FS_ENTRY_POINT :: "fragment_main";
CS_ENTRY_POINT :: "compute_main";
#import "String";
#import "File";
#import "Basic";
#scope_file
#import "stb_image";
