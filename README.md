# Gaco
Graphics and Compute library for Jai in the style of [bgfx](https://github.com/bkaradzic/bgfx). Currently supports Windows and Linux through D3D11 and OpenGL.

## Features
- No boilerplate.
- No need to specify input-layout for vertex/instance buffers, it's automatically created using reflection.
- Single source for shaders (HLSL).

## Getting Started
Put `Gaco/` to your local modules directory.
There are lots of examples included in the `examples/` folder. You can go through them to get an understanding of how the library works.

```jai
#import "Window_Creation";
#import "Input";
Gaco :: #import "Gaco";

main :: () {
    window := create_window(1280, 720, "My Beautiful Window");
    Gaco.init(window);

    vertices := ...;
    indices := ...;

    vertex_buffer := Gaco.create_buffer(vertices, .Vertex);
    index_buffer := Gaco.create_buffer(indices, .Index);

    // Already compiled with Gaco.compile_shader()
    shader := Gaco.load_shader("my_shader.gaco");

    quit := false;
    while !quit {
        update_window_events();
        for get_window_resizes() {
            Gaco.resize(it.width, it.height);
        }
        for events_this_frame {
            if it.type == .QUIT quit = true;
        }

        Gaco.clear(.{1.0, 0.2, 0.5, 1.0});
        Gaco.set_shader(shader);
        Gaco.bind_buffer(vertex_buffer);
        Gaco.bind_buffer(index_buffer);

        Gaco.draw(true, indices.count);

        Gaco.present(1); // Present with vsync
    }

}
```

## Concepts

### Module parameters
```jai
#module_parameters (BACKEND := DEFAULT_BACKEND, DEBUG := false, REQUEST_HIGH_PERFORMANCE_GPU := true);
```

- **`BACKEND`**: `.D3D11`, `.OpenGL`. Default is selected automatically per OS.
- **`DEBUG`**: enables validation, debug names etc.
  - For the D3D11 backend, you need to import d3d11 like this when DEBUG is enabled (because it's a program parameter):
    ```jai
    #import "d3d11"()(INCLUDE_DEBUG_BINDINGS=true);
    ```
- **`REQUEST_HIGH_PERFORMANCE_GPU`**: useful for hybrid-graphics laptops.

### Initialization
`init(window=)`: initializes the library. You can pass an invalid window if you don't need to render anything (compute-only application).

`resize(width=, height=, msaa, color_format, depth_format)`: (re)creates and returns the render target that all drawing happens into by default.

### Shaders
Shaders are compiled from a single HLSL source file containing up to three entry points, selected by `Shader_Type` flags (`.Vertex`, `.Fragment`, `.Compute`, combinable):

```jai
VS_ENTRY_POINT :: "vertex_main";
FS_ENTRY_POINT :: "fragment_main";
CS_ENTRY_POINT :: "compute_main";
```

Two ways to get a `Shader`:

1. **Bytecode (SPIR-V, DXBC)**: `compile_shader_to_bytecode` and `load_shader_from_bytecode`.
2. **Gaco File**: `compile_shader` / `compile_shader_from_memory` and `load_shader` / `load_shader_from_memory`.
We have a lightweight custom file format that combines several shader stages (and texture/sampler mappings for OpenGL) to one file and I think it's a lot easier to work with.

Note that the compile output is backend-specific, a file built with one backend won't load under another backend so make sure to select the right one.

### Buffers
Use `create_buffer` to create a buffer and initialize it. Buffer is a parameterized struct with the following types. You can use `bind_buffer` for each type.

```jai
Buffer_Type :: enum u32 { Vertex; Index; Constant; Copy; Indirect; Structured; Structured_RW; }
```
- **`Vertex`**: Buffer for setting vertices. Binding slot 0 is vertex data, slot 1 is instance data.
- **`Index`**: Buffer for setting indices corresponding to bound vertices. Stride must be 2 (`u16`) or 4 (`u32`).
- **`Constant`**: constant/uniform buffer, bound per shader stage with `bind_to: Shader_Type`.
- **`Structured`**: read-only structured buffer, bound per shader stage.
- **`Structured_RW`**: read/write structured buffer, compute-shader only.
- **`Indirect`**: draw/dispatch argument buffer for `draw_indirect` / `dispatch_compute_indirect`.
- **`Copy`**: a staging/readback buffer.

To upload data to an existing buffer, use:
- **`update_buffer`**: for `.Default`-usage buffers.
- **`write_buffer`**: for `.Dynamic`-usage buffers.
- **`map_buffer/unmap_buffer`** for `.Dynamic`-usage or `Copy` buffers.

### Textures
```jai
create_texture :: (data: []*u8, width: u32, height: u32,
                    array_count_or_depth: u32 = 1, mip_levels_or_msaa: u32 = 1,
                    format := Texture_Format.RGBA8, flags := Texture_Flags.Sampled,
                    debug_name := "") -> Texture
```

One function creates every texture shape, behavior is selected via `Texture_Flags`:

```jai
Texture_Flags :: enum_flags u32 {
    Cubemap; Sampled; Generate_Mips; Is_3D; Multisample; Render_Target; Copy; Compute_RW;
}
```

- 2D Texture: Default (`array_count_or_depth = 1`).
- 2D Array: Set `array_count_or_depth = N`.
- Cubemap: `.Cubemap`, with `array_count_or_depth = 6` (or `6 * N` for cube arrays).
- 3D Volume: `.Is_3D`, with `array_count_or_depth = depth`.
- MSAA render target: `.Multisample`, `mip_levels_or_msaa = sample count`.
- UAV / Storage Image: `.Compute_RW` (`RWTexture2D` in HLSL).
- Staging / Readback: `.Copy`.

`data` is a flat array of subresource pointers, laid out as `[array/face index][mip level]` (all mips of element 0, then all mips of element 1, and so on).

Convenience loaders:
- `create_texture_from_file` / `create_texture_from_memory`: single image.
- `create_texture_array_from_files`: builds a texture array from N same-sized images.

Update an existing texture's contents with `update_texture` (whole texture, a `Rect`, or a `Box` for 3D/array subregions), or `map_texture`/`unmap_texture` for `.Copy` textures. `copy_texture` and `copy_from_render_target` do GPU-side blits/copies without a CPU round-trip.
