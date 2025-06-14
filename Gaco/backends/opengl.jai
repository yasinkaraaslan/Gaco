init :: (window: Window_Type, wanted_msaa: u32 = 4) {
	gl_create_context(window, 4, 6, false, DEBUG, cast(s32) wanted_msaa);
	#if DEBUG gl_enable_debug_output(true);

	Window = window;
}
Shader :: struct {
	program: u32;
}

Texture :: struct {}

clear :: (r: float, g: float, b: float, a: float) {
	glClearColor(r, g, b, a);
	glClearDepth(1.0);
	// glClearStencil(0);
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
}

resize :: (width: int, height: int) {
	glViewport(0, 0, cast(u32)width, cast(u32) height);
}

present :: () {
	#if OS == .WINDOWS {
   	dc := GetDC(Window);
   	SwapBuffers(dc);
   }
	else #if OS == .LINUX {
		// Todo
		assert(false);
	}
}

compile_shader_to_bytecode :: (source: string, type: Shader_Type, shader_file_name: string) -> bytecode: Shader_Bytecode, ok: bool {
	compile :: (type: Shader_Type) -> string #expand {
		entry_point: string;

		dxc_type : DXC.Shader_Type;

		if type == {
		case .Vertex;
			entry_point = VS_ENTRY_POINT;
			dxc_type = .Vertex;
		case .Fragment;
			entry_point = FS_ENTRY_POINT;
			dxc_type = .Fragment;
		case .Compute;
			entry_point = CS_ENTRY_POINT;
			dxc_type = .Compute;
		}
		version := "5_0";
		args := DXC.Dxc_Shader_Compiler_Args.{
			shader_name = path_strip_extension(`shader_file_name),
			shader_source = `source,
			shader_model_version = version,
			shader_type = dxc_type,
			entry_point = entry_point,
			add_debug_info = false, // If you enable this the program crashes at compile time for some reason. Probably a @CompilerBug
			skip_optimization = DEBUG,
			compile_as_spirv = true,
			warnings_as_error = true,
			use_spirv_1_4 = false,
		};
		result := DXC.DXC_Compile(args);
		if !result {
			`return .{}, false;
		}
		return cast(string)result;
	}
	bytecode: Shader_Bytecode;
	if type & .Vertex    bytecode.vs = compile(.Vertex);
	if type & .Fragment  bytecode.fs = compile(.Fragment);
	if type & .Compute   bytecode.cs = compile(.Compute);

	return bytecode, true;
}

load_shader :: (file_name: string, type: Shader_Type) -> Shader {
	shader: Shader;
	bytecode := load_shader_bytecode(file_name, type);


	if type & .Compute {
		assert(type == .Compute, "Compute shader cannot be used with other shader types.");
	}

	if type & .Vertex {
	}

	if type & .Fragment {
	}
}

#scope_module
VS_EXTENSION :: ".spvs";
FS_EXTENSION :: ".spfs";
CS_EXTENSION :: ".spcs";

#scope_file
Window : Window_Type;

#import "GL"(DUMP_GL_ERRORS=DEBUG);
#import "Window_Type";
#if OS == .WINDOWS #import "Windows";
else #if OS == .LINUX #import "X11";
DXC :: #import "dxc_compiler";
