// NOTE(Yasin): Binding to specific stages doesn't make sense in OpenGL!!!
// Find a way out of this before release!
//
// Option 1: Provide the parameter but just for compatibility, so it wouldn't make any difference in OpenGL.
// Option 2: Set it for every stage in D3D11. (slow)
// Option 3: Use glGetProgramPipelineiv and glProgramUniform somehow, which would bind it to a specific shader instead of a stage.


Shader :: struct {
    type: Shader_Type;
    input_layout: *ID3D11InputLayout;
    vertex_shader: *ID3D11VertexShader;
    fragment_shader: *ID3D11PixelShader;
    compute_shader: *ID3D11ComputeShader;
}

Buffer :: struct (type: Buffer_Type) {
    buffer: *ID3D11Buffer;
    size: u32;
    stride: u32;
    #if type == .Structured {
        srv: *ID3D11ShaderResourceView;
    }
    else #if type == .RWStructured {
        // @Incomplete: INDIRECT
        uav: *ID3D11UnorderedAccessView;
    }
};

Sampler :: struct {
    state: *ID3D11SamplerState;
}

Texture :: struct {
    union {
        texture2d: *ID3D11Texture2D;
        texture3d: *ID3D11Texture3D;
    }
    union {
        resource_view: *ID3D11ShaderResourceView;
        unordered_access_view: *ID3D11UnorderedAccessView;
    }
    width, height, stride: u32;
    depth: u32 = 1;
    flags: Texture_Flags;
};

Render_Target :: struct {
    // We could hardcode 8 here because that is the maximum number of color views D3D11 supports.
    // Which would increase the struct size but wouldn't require heap allocation.
    color_views: []*ID3D11RenderTargetView;
    depth_stencil_view: *ID3D11DepthStencilView;
}

// @Incomplete: You cannot create or destroy these
Blend_State :: struct {
    state: *ID3D11BlendState;
}

Rasterizer_State :: struct {
    state: *ID3D11RasterizerState;
}

Depth_Stencil_State :: struct {
    state: *ID3D11DepthStencilState;
}

is_empty :: (texture: Texture) -> bool {
    return texture.texture2d == null; // and texture3d
}

is_empty :: (using shader: Shader) -> bool {
    empty_vs := type & .Vertex   && (!vertex_shader || !input_layout);
    empty_fs := type & .Fragment && !fragment_shader;
    empty_cs := type & .Compute  && !compute_shader;

    return type == .Unspecified || empty_vs || empty_fs || empty_cs;
}

is_empty :: (using render_target: Render_Target) -> bool {
    return !color_views && !depth_stencil_view;
}

init :: (window: HWND, wanted_msaa: u32 = 4) {
    flags: D3D11_CREATE_DEVICE_FLAG;
    #if DEBUG flags |= .DEBUG;
    feature_levels := D3D_FEATURE_LEVEL.[._11_1];

    // NOTE(Yasin): D3D11 just spins a bunch of threads for lots of different things.
    // MSDN says we can prevent it by passing .PREVENT_INTERNAL_THREADING_OPTIMIZATIONS but it still
    // seems to create about 20 threads (can probably disabled in some driver setting),
    // this isn't recommended also. I don't know man...
    // flags |= .PREVENT_INTERNAL_THREADING_OPTIMIZATIONS;

    // @@ Explain why this is here.
    flags |= .SINGLETHREADED;
    hr := D3D11CreateDevice(null, .HARDWARE, null, xx flags, feature_levels.data, feature_levels.count, D3D11_SDK_VERSION, *device, null, *device_context);
    check_hr("D3D11CreateDevice");

    #if DEBUG {
        // When you call SetBreakOnSeverity, D3D11 crashes on the specified severity.
        // So we have to put our own exception handler to tell what is going on.
        init_exception_handler();
    }

    // We might be trying to create a compute only application.
    if window == null return;

    swap_chain_desc := DXGI_SWAP_CHAIN_DESC1.{
        Width = 0, Height = 0, // Get from the window.
        Format = .R8G8B8A8_UNORM,
        BufferCount = 1,
        BufferUsage = .RENDER_TARGET_OUTPUT,
        SampleDesc = .{Count = wanted_msaa, Quality = 0},
    };

    dxgi_factory: *IDXGIFactory2;
    {
        dxgi_device: *IDXGIDevice2;
        hr = IUnknown_QueryInterface(device, *uid(IDXGIDevice2_UUID), xx *dxgi_device);
        check_hr("IUnknown.QueryInterface");
        dxgi_adapter: *IDXGIAdapter;
        hr = IDXGIDevice_GetAdapter(dxgi_device, *dxgi_adapter);
        check_hr("IDXGIDevice.GetAdapter");

        hr = IDXGIObject_GetParent(dxgi_adapter, *uid(IDXGIFactory2_UUID), xx *dxgi_factory);
        check_hr("IDXGIObject.GetParent");

        safe_release(dxgi_adapter);
        safe_release(dxgi_device);
    }
    hr = IDXGIFactory2_CreateSwapChainForHwnd(dxgi_factory, device, window, *swap_chain_desc, null, null, *swap_chain);
    check_hr("IDXGIFactory2.CreateSwapChainForHwnd");

    hr = IDXGIFactory_MakeWindowAssociation(dxgi_factory, window, xx DXGI_MWA.NO_ALT_ENTER);
    check_hr("IDXGIFactory.MakeWindowAssociation");
    safe_release(dxgi_factory);


    msaa = wanted_msaa;

    init_preloaded_modes();
    set_primitive_type(.Triangle_List);

    // There are very few cases where one wouldn't want depth testing.
    // So we enable it by default.
    set_depth_stencil_mode(.Depth_Stencil);
}

deinit :: () {
    #if DEBUG
        log_messages_and_get_last();

    for * blend_modes {
        safe_release_and_reset(it);
    }
    for * rasterizer_modes {
        safe_release_and_reset(it);
    }
    for * depth_stencil_modes {
        safe_release_and_reset(it);
    }

    destroy_render_target(*window_render_target);
    safe_release_and_reset(*swap_chain);
    safe_release_and_reset(*device_context);
    safe_release_and_reset(*device);
}

create_buffer :: (data: *void, count: u32, stride: u32, $type: Buffer_Type, usage := Buffer_Usage.Default) -> Buffer(type) {
    buffer: Buffer(type);
    buffer.size = count * stride;
    buffer.stride = stride;

    bd := D3D11_BUFFER_DESC.{
        ByteWidth = buffer.size
    };
    if usage == {
    case .Default;
        bd.Usage = .DEFAULT;
    case .Immutable;
        bd.Usage = .IMMUTABLE;
    case .Dynamic;
        bd.Usage = .DYNAMIC;
        bd.CPUAccessFlags = .WRITE;
    }

    // These are seperate in OpenGL while the same in D3D11
    INDIRECT :: type == .Draw_Indirect || type == .Dispatch_Indirect;

    #if type == {
    case .Vertex;
        bd.BindFlags = .VERTEX_BUFFER;
    case .Index;
        bd.BindFlags = .INDEX_BUFFER;
    case .Constant;
        bd.BindFlags = .CONSTANT_BUFFER;
    case .Structured;
        bd.BindFlags = .SHADER_RESOURCE;
        bd.MiscFlags = .BUFFER_STRUCTURED;
        bd.StructureByteStride = stride;
    case .RWStructured;
        bd.BindFlags = .UNORDERED_ACCESS;
        bd.MiscFlags = .BUFFER_STRUCTURED;
        bd.StructureByteStride = stride;
    case .Copy;
        bd.Usage = .STAGING;
        bd.CPUAccessFlags |= .READ;
    }

    #if INDIRECT {
        // If you are creating a draw indirect buffer you probably want unordered access.
        // But I am not sure about the performance implications, so this is @Incomplete.
        // bd.BindFlags = .UNORDERED_ACCESS;

        bd.MiscFlags = .DRAWINDIRECT_ARGS;
    }

    init_data: *D3D11_SUBRESOURCE_DATA = null;
    if data != null {
        init_data = * (D3D11_SUBRESOURCE_DATA.{
            pSysMem = data
        });
    }

    hr := ID3D11Device_CreateBuffer(device, *bd, init_data, *buffer.buffer);
    check_hr("ID3D11Device.CreateBuffer", #code `return .{});

    #if type == .Structured {
        srv_desc := D3D11_SHADER_RESOURCE_VIEW_DESC.{
            ViewDimension = .BUFFER,
            Buffer.NumElements = count
        };
        hr = ID3D11Device_CreateShaderResourceView(device, buffer.buffer, *srv_desc, *buffer.srv);
        check_hr("ID3D11Device.CreateShaderResourceView", #code `return .{});
    }
    else #if type == .RWStructured { // @Incomplete: || INDIRECT
        uav_desc := D3D11_UNORDERED_ACCESS_VIEW_DESC.{
            ViewDimension = .BUFFER,
            Buffer.NumElements = count
        };
        hr = ID3D11Device_CreateUnorderedAccessView(device, buffer.buffer, *uav_desc, *buffer.uav);
        check_hr("ID3D11Device.CreateUnorderedAccessView", #code `return .{});
    }

    return buffer;
}

bind_buffer :: (buffer: Buffer(.Vertex), slot: u32 = 0, offset: u32 = 0) {
    ID3D11DeviceContext_IASetVertexBuffers(device_context, slot, 1, *buffer.buffer, *buffer.stride, *offset);
}

bind_buffer :: (buffer: Buffer(.Index)) {
    format: DXGI_FORMAT;
    if      buffer.stride == 2 format = .R16_UINT;
    else if buffer.stride == 4 format = .R32_UINT;
    ID3D11DeviceContext_IASetIndexBuffer(device_context, buffer.buffer, format, 0);
}

bind_buffer :: (buffer: Buffer(.Constant), slot: u32 = 0) {
    ID3D11DeviceContext_VSSetConstantBuffers(device_context, slot, 1, *buffer.buffer);
    ID3D11DeviceContext_PSSetConstantBuffers(device_context, slot, 1, *buffer.buffer);
    if shader_state & .Compute
        ID3D11DeviceContext_CSSetConstantBuffers(device_context, slot, 1, *buffer.buffer);
}

bind_buffer :: (buffer: Buffer(.Structured), slot: u32 = 0) {
    ID3D11DeviceContext_VSSetShaderResources(device_context, slot, 1, *buffer.srv);
    ID3D11DeviceContext_PSSetShaderResources(device_context, slot, 1, *buffer.srv);
    if shader_state & .Compute
        ID3D11DeviceContext_CSSetShaderResources(device_context, slot, 1, *buffer.srv);
}

// TODO(Yasin): OMSetRenderTargetsAndUnorderedAccessViews
bind_buffer :: (buffer: Buffer(.RWStructured), slot: u32 = 0) {
    ID3D11DeviceContext_CSSetUnorderedAccessViews(device_context, slot, 1, *buffer.uav, null);
}

map_buffer :: (buffer: *Buffer, flags: Map_Flags) -> *void {
    subresource: D3D11_MAPPED_SUBRESOURCE;
    d3d11_flags: D3D11_MAP;
    if flags & .Read  d3d11_flags |= .READ;
    if flags & .Write {
        #if buffer.type == .Copy d3d11_flags |= .WRITE;
        else                     d3d11_flags |= .WRITE_DISCARD;
    }

    hr := ID3D11DeviceContext_Map(device_context, buffer.buffer, 0, d3d11_flags, 0, *subresource);
    check_hr("ID3D11DeviceContext.Map", #code return null);
    return subresource.pData;
}

unmap_buffer :: (buffer: *Buffer) {
    ID3D11DeviceContext_Unmap(device_context, buffer.buffer, 0);
}

map_texture :: (texture: *Texture, flags: Map_Flags) -> *void {
    // @Cutnpaste from the top
    d3d11_subresource: D3D11_MAPPED_SUBRESOURCE;
    d3d11_flags: D3D11_MAP;

    if flags & .Read  d3d11_flags |= .READ;
    if flags & .Write d3d11_flags |= .WRITE_DISCARD;

    hr := ID3D11DeviceContext_Map(device_context, texture.texture2d, 0, d3d11_flags, 0, *d3d11_subresource);
    check_hr("ID3D11DeviceContext.Map", #code return null);
    return d3d11_subresource.pData;
}

unmap_texture :: (texture: *Texture, subresource: u32 = 0) {
    ID3D11DeviceContext_Unmap(device_context, texture.texture2d, subresource);
}

update_buffer :: (buffer: *Buffer, data: *void) {
    ID3D11DeviceContext_UpdateSubresource(device_context, buffer.buffer, 0, null, data, buffer.stride, 0);
}

// @Incomplete: Cannot update sub texture3d
update_texture :: (texture: *Texture, data: *void, rect: Rect, subresource: u32 = 0) {
    row := cast(u32)rect.width * texture.stride;
    box := box_from_rect(rect);
    ID3D11DeviceContext_UpdateSubresource(device_context, texture.texture2d, subresource, *box, data, row, 0);
}

update_texture :: (texture: *Texture, data: *void, box: Box, subresource: u32 = 0) {
    row := cast(u32)box.width * texture.stride;
    d_box := box_from_box(box);
    ID3D11DeviceContext_UpdateSubresource(device_context, texture.texture3d, subresource, *d_box, data, row, row * texture.height);

}

update_texture :: (using texture: *Texture, data: *void, subresource: u32 = 0) {
    row := width * stride;
    ID3D11DeviceContext_UpdateSubresource(device_context, texture2d, subresource, null, data, row, row * height);
}

// Allocates on temp
// NOTE(Yasin): This creates a huge performance penalty.
read_buffer :: (buffer: *Buffer, copy_buffer_to_use: *Buffer(.Copy) = null) -> *void {
    buffer_to_map: *Buffer(.Copy) = ---;

    if copy_buffer_to_use {
        buffer_to_map = copy_buffer_to_use;
    }
    else {
        buffer_to_map = * (create_buffer(null, buffer.size / buffer.stride, buffer.stride, .Copy));
    }

    copy_buffer(buffer, buffer_to_map);

    data := alloc(buffer.size,, temp);

    mapped_data := map_buffer(buffer_to_map, .Read);
    memcpy(data, mapped_data, buffer.size);
    unmap_buffer(buffer_to_map);
    if !copy_buffer_to_use destroy_buffer(buffer_to_map);
    return data;
}

write_buffer :: (buffer: *Buffer, data: *void, size: int) {
    write :: (buffer_to_write: *Buffer) #expand {
        mapped_data := map_buffer(buffer_to_write, .Write);
        memcpy(mapped_data, data, size);
        unmap_buffer(buffer_to_write);
    }

    #if buffer.type == .RWStructured {
        buffer_to_write := * (create_buffer(null, buffer.size / buffer.stride, buffer.stride, .Copy, .Dynamic));
        write(buffer_to_write);
        copy_buffer(buffer_to_write, buffer);
        destroy_buffer(buffer_to_write);
    }
    else {
        write(buffer);
    }
}

copy_buffer :: (from: Buffer, to: *Buffer) {
    ID3D11DeviceContext_CopyResource(device_context, to.buffer, from.buffer);
}

destroy_buffer :: (buffer: *Buffer) {
    safe_release_and_reset(*buffer.buffer);

    #if buffer.type == .Structured   {
        safe_release_and_reset(*buffer.srv);
    }
    else #if buffer.type == .RWStructured {
        safe_release_and_reset(*buffer.uav);
    }

    buffer.size, buffer.stride = 0;
}

destroy_texture :: (texture: *Texture) {
    if texture.flags & .Is_3D {
        safe_release_and_reset(*texture.texture3d);
    }
    else {
        safe_release_and_reset(*texture.texture2d);
    }

    if texture.flags & .Compute_RW {
        safe_release_and_reset(*texture.unordered_access_view);
    }
    else {
        safe_release_and_reset(*texture.resource_view);
    }

    texture.width, texture.height, texture.stride = 0;
    texture.depth = 1;
    texture.flags = .None;
}

destroy_shader :: (using shader: *Shader) {
    if type & .Vertex {
        safe_release_and_reset(*vertex_shader);
        safe_release_and_reset(*input_layout);
    }
    if type & .Fragment
        safe_release_and_reset(*fragment_shader);
    if type & .Compute
        safe_release_and_reset(*compute_shader);
}

compile_shader_to_bytecode :: (source: string, type: Shader_Type, shader_name: string) -> Shader_Bytecode, bool {
    bytecode: Shader_Bytecode;
    flags := D3DCOMPILE.ENABLE_STRICTNESS;
    defines: []string;
    #if DEBUG {
        flags |= .DEBUG | .SKIP_OPTIMIZATION;
    }
    compile :: (entry_point: string, target: string) -> string #expand {
        output, errors, hr := D3DCompile(source, shader_name, defines, D3D_COMPILE_STANDARD_FILE_INCLUDE, entry_point, target, xx flags, 0);
        defer free(errors);

        check_hr("D3DCompile", #code {
            free(bytecode);
            log_error(errors);
            `return .{}, false;
        });
        return output;
    }

    if type & .Vertex    bytecode.vs = compile(VS_ENTRY_POINT, "vs_5_0");
    if type & .Fragment  bytecode.fs = compile(FS_ENTRY_POINT, "ps_5_0");
    if type & .Compute   bytecode.cs = compile(CS_ENTRY_POINT, "cs_5_0");

    return bytecode, true;
}

load_shader_from_bytecode :: (bytecode: Shader_Bytecode, type: Shader_Type) -> Shader {
    shader: Shader;
    if type & .Vertex {
        hr := ID3D11Device_CreateVertexShader(device, bytecode.vs.data, xx bytecode.vs.count, null, *shader.vertex_shader);
        check_hr("ID3D11Device.CreateVertexShader", #code `return .{});

        shader.input_layout = get_input_layout_from_bytecode(bytecode.vs);

        #if DEBUG {
            ID3D11DeviceChild_SetPrivateData(shader.vertex_shader, *uid(WKPDID_D3DDebugObjectName), VS_ENTRY_POINT.count, VS_ENTRY_POINT.data);
        }
    }

    if type & .Fragment {
        hr := ID3D11Device_CreatePixelShader(device, bytecode.fs.data, xx bytecode.fs.count, null, *shader.fragment_shader);
        check_hr("ID3D11Device.CreatePixelShader", #code `return .{});

        #if DEBUG {
            ID3D11DeviceChild_SetPrivateData(shader.fragment_shader,*uid(WKPDID_D3DDebugObjectName), FS_ENTRY_POINT.count, FS_ENTRY_POINT.data);
        }
    }

    if type & .Compute {
        hr := ID3D11Device_CreateComputeShader(device, bytecode.cs.data, xx bytecode.cs.count, null, *shader.compute_shader);
        check_hr("ID3D11Device.CreateComputeShader", #code `return .{});

        #if DEBUG {
            ID3D11DeviceChild_SetPrivateData(shader.compute_shader, *uid(WKPDID_D3DDebugObjectName), CS_ENTRY_POINT.count, CS_ENTRY_POINT.data);
        }
    }


    shader.type = type;
    return shader;
}

clear :: (render_target: Render_Target, r: float, g: float, b: float, a: float, depth := 1.0, stencil: u8 = 0, $flags: Clear_Flags = .Color | .Depth | .Stencil) {
    #if flags & .Color {
        color := float.[r, g, b, a];
        for render_target.color_views {
            ID3D11DeviceContext_ClearRenderTargetView(device_context, it, *color);
        }
    }

    d3d11_clear: D3D11_CLEAR_FLAG;
    #if flags & .Depth
        d3d11_clear |= .DEPTH;
    #if flags & .Stencil
        d3d11_clear |= .STENCIL;

    #if flags & .Depth || flags & .Stencil {
        ID3D11DeviceContext_ClearDepthStencilView(device_context, render_target.depth_stencil_view, cast(u32) d3d11_clear, depth, stencil);
    }
}

clear :: inline (r: float, g: float, b: float, a: float, depth := 1.0, stencil: u8 = 0, $flags: Clear_Flags = .Color | .Depth | .Stencil) {
    clear(window_render_target, r, g, b, a, depth, stencil, flags);
}

set_shader :: (shader: Shader) {
    if shader.type & .Vertex {
        ID3D11DeviceContext_IASetInputLayout(device_context, shader.input_layout);
        ID3D11DeviceContext_VSSetShader(device_context, shader.vertex_shader, null, 0);
        if !shader.vertex_shader  shader_state &= ~.Vertex;
        else shader_state |= .Vertex;
    }
    if shader.type & .Fragment {
        ID3D11DeviceContext_PSSetShader(device_context, shader.fragment_shader, null, 0);
        if !shader.fragment_shader  shader_state &= ~.Fragment;
        else shader_state |= .Fragment;
    }
    if shader.type & .Compute {
        ID3D11DeviceContext_CSSetShader(device_context, shader.compute_shader, null, 0);
        if !shader.compute_shader shader_state &= ~.Compute;
        else shader_state |= .Compute;
    }
}

set_primitive_type :: (primitive_type: Primitive_Type) {
    topology: D3D11_PRIMITIVE_TOPOLOGY;
    if #complete primitive_type == {
    case .Line_List;
        topology = .LINELIST;
    case .Line_Strip;
        topology = .LINESTRIP;
    case .Triangle_List;
        topology = .TRIANGLELIST;
    case .Triangle_Strip;
        topology = .TRIANGLESTRIP;
    }
    ID3D11DeviceContext_IASetPrimitiveTopology(device_context, topology);
}

set_scissor :: (rect: Rect) {
    d3d11_rect := D3D11_RECT.{
        left = rect.x,
        top = rect.y,
        right = rect.x + rect.width,
        bottom = rect.y + rect.height
    };

    ID3D11DeviceContext_RSSetScissorRects(device_context, 1, *d3d11_rect);
}


// HLSL doesn't have a way to specify a viewport index (except for geometry shaders, which we don't support).
// So there is no reason for a 'set_viewports'.
set_viewport :: (x: float, y: float, width: float, height: float, near_depth := 0.0, far_depth := 1.0) {
    vp: D3D11_VIEWPORT;
    vp.TopLeftX = x;
    vp.TopLeftY = y;
    vp.Width = width;
    vp.Height = height;
    vp.MinDepth = near_depth;
    vp.MaxDepth = far_depth;
    ID3D11DeviceContext_RSSetViewports(device_context, 1, *vp);
}

set_blend_mode :: (mode: Blend_Mode) {
    ID3D11DeviceContext_OMSetBlendState(device_context, blend_modes[mode], null, SampleMask=0xFFFFFFFF);
}

set_rasterizer_mode :: (mode: Rasterizer_Mode) {
    ID3D11DeviceContext_RSSetState(device_context, rasterizer_modes[mode]);
}

set_depth_stencil_mode :: (mode: Depth_Stencil_Mode) {
    ID3D11DeviceContext_OMSetDepthStencilState(device_context, depth_stencil_modes[mode], StencilRef=0xFF);
}
// base_vertex only makes sense in indexed drawing.
draw :: ($indexed: bool, count: u32, first: u32 = 0, base_vertex: s32 = 0) {
    #if indexed {
        ID3D11DeviceContext_DrawIndexed(device_context, count, first, base_vertex);
    }
    else {
        ID3D11DeviceContext_Draw(device_context, count, first);
    }
}

draw_instanced :: ($indexed: bool, count: u32, instance_count: u32, first: u32 = 0, first_instance: u32 = 0, base_vertex: s32 = 0) {
    #if indexed {
        ID3D11DeviceContext_DrawIndexedInstanced(device_context, count, instance_count, first, base_vertex, first_instance);
    }
    else {
        ID3D11DeviceContext_DrawInstanced(device_context, count, instance_count, first, first_instance);
    }
}

draw_indirect :: ($indexed: bool, buffer: Buffer(.Draw_Indirect), byte_offset: u32 = 0) {
    #if indexed {
        ID3D11DeviceContext_DrawIndexedInstancedIndirect(device_context, buffer.buffer, byte_offset);
    }
    else {
        ID3D11DeviceContext_DrawInstancedIndirect(device_context, buffer.buffer, byte_offset);
    }
}

dispatch_compute :: (num_groups_x: u32, num_groups_y: u32, num_groups_z: u32) {
    ID3D11DeviceContext_Dispatch(device_context, num_groups_x, num_groups_y, num_groups_z);
}

// Actually, both Draw_Indirect and Dispatch_Indirect would work here since they are the same in D3D11.
// But just to be compatible with a potential OpenGL backend.
dispatch_compute_indirect :: (buffer: Buffer(.Dispatch_Indirect), byte_offset: u32 = 0) {
    ID3D11DeviceContext_DispatchIndirect(device_context, buffer.buffer, byte_offset);
}

present :: (interval: u32 = 1) {
    hr := IDXGISwapChain_Present(swap_chain, interval, 0);
    check_hr("IDXGISwapChain_Present", #code {});
}

create_render_target :: (color_textures: []Texture, depth_stencil_texture: Texture) -> Render_Target {
    render_target: Render_Target;
    if color_textures {
        render_target.color_views = NewArray(color_textures.count, *ID3D11RenderTargetView);

        for color_textures {
            hr := ID3D11Device_CreateRenderTargetView(device, it.texture2d, null, *render_target.color_views[it_index]);
            check_hr("ID3D11Device.CreateRenderTargetView", #code return .{});
        }
    }

    if !is_empty(depth_stencil_texture) {
        hr := ID3D11Device_CreateDepthStencilView(device, depth_stencil_texture.texture2d, null, *render_target.depth_stencil_view);
        check_hr("ID3D11Device.CreateDepthStencilView", #code return .{});
    }
    return render_target;
}

set_render_target :: (using render_target: Render_Target) {
    ID3D11DeviceContext_OMSetRenderTargets(device_context, cast(u32)color_views.count, color_views.data, depth_stencil_view);
}

destroy_render_target :: (render_target: *Render_Target) {
    for * render_target.color_views {
        safe_release_and_reset(it);
    }
    array_free(render_target.color_views);

    safe_release_and_reset(*render_target.depth_stencil_view);
}

resize :: (width: int, height: int) -> window_render_target: Render_Target {
    // This doesn't seem to be necessary, but just to be safe...
    set_render_target(.{});
    destroy_render_target(*window_render_target);

    hr := IDXGISwapChain_ResizeBuffers(swap_chain, 0, cast(u32)width, cast(u32)height, .UNKNOWN, 0);
    check_hr("IDXGISwapChain.ResizeBuffers", #code `return .{});

    back_buffer: Texture;
    hr = IDXGISwapChain_GetBuffer(swap_chain, 0, *uid(ID3D11Texture2D_UUID), xx *back_buffer.texture2d);
    check_hr("IDXGISwapChain.GetBuffer", #code `return .{});

    depth_stencil_texture := create_texture(.[], cast(u32)width, cast(u32)height, 1, 1, msaa, flags=.Depth_Stencil | .Multisample);
    window_render_target = create_render_target(.[back_buffer], depth_stencil_texture);

    destroy_texture(*depth_stencil_texture);
    destroy_texture(*back_buffer);

    set_render_target(*window_render_target);
    set_viewport(0, 0, cast(float)width, cast(float)height);

    return window_render_target;
}

// @@ Data could be either []*u8 or [][]u8.
// I am not sure which one makes more sense.

// Data is an array for texture arrays and mipmapping.
// Index = mip slice + (array slice * mip levels)
// Image 0 mip data | Image 1 mip data | ...

// @Incomplete: We should just have a format parameter and remove channels.
create_texture :: (data: []*u8, width: u32, height: u32, channels: u32, array_count_or_depth: u32 = 1, mip_levels_or_msaa: u32 = 1, format := Texture_Format.Default, flags := Texture_Flags.None) -> Texture {
    generate_mips := (flags & .Generate_Mips) && mip_levels_or_msaa > 1;

    d3d11_format: DXGI_FORMAT;
    bind_flags: D3D11_BIND_FLAG;
    misc_flags: D3D11_RESOURCE_MISC_FLAG;

    usage := D3D11_USAGE.DEFAULT;
    access_flags: D3D11_CPU_ACCESS_FLAG;

    // Pick the flags

    if flags & .Compute_RW
        bind_flags = .UNORDERED_ACCESS;
    else if flags & .Render_Target
        bind_flags = .RENDER_TARGET;
    else if flags & .Depth_Stencil
        bind_flags = .DEPTH_STENCIL;
    else if flags & .Copy {
        usage = .STAGING;
        access_flags |= .READ;
    }
    else
        bind_flags = .SHADER_RESOURCE;

    if generate_mips {
        // @Speed: We would probably want to create a seperate render target texture
        // and copy it to our newly generated texture.
        bind_flags |= .RENDER_TARGET;
        misc_flags |= .GENERATE_MIPS;
    }

    if flags & .Cubemap
        misc_flags |= .TEXTURECUBE;

    // Pick the format

    formats: [4]DXGI_FORMAT;
    bytes_per_block := channels;
    if format == {
    case .U32;
        formats = DXGI_FORMAT.[.R32_UINT, .R32G32_UINT, .R32G32B32_UINT, .R32G32B32A32_UINT];
        bytes_per_block *= 4;
    case .SRGB;
        formats[3] = .R8G8B8A8_UNORM_SRGB;
    case .Float16;
        formats = DXGI_FORMAT.[.R16_FLOAT, .R16G16_FLOAT, .UNKNOWN, .R16G16B16A16_FLOAT];
        bytes_per_block *= 2;
    case .Float32;
        formats = DXGI_FORMAT.[.R32_FLOAT, .R32G32_FLOAT, .R32G32B32_FLOAT, .R32G32B32A32_FLOAT];
        bytes_per_block *= 4;
    case .BC6U;
        d3d11_format = .BC6H_UF16;
    case .BC6S;
        d3d11_format = .BC6H_SF16;
    case .BC7;
        d3d11_format = .BC7_UNORM;
    case .BC7_SRGB;
        d3d11_format = .BC7_UNORM_SRGB;
    case .Default;
        if flags & .Depth_Stencil
            d3d11_format = .D24_UNORM_S8_UINT;
        else
            formats = DXGI_FORMAT.[.R8_UNORM, .R8G8_UNORM, .UNKNOWN, .R8G8B8A8_UNORM];
    case;
        log_error("[Gaco] Unknown texture format: %", format);
        return .{};
    }

    if is_block_compression(format)
        bytes_per_block = 16;

    if !d3d11_format {
        d3d11_format = formats[channels-1];

        if !d3d11_format {
            log_error("[Gaco] Error while creating texture: % channels with format % is not compatible.", channels, format);
            return .{};
        }
    }

    // Create the thing
    texture := Texture.{width=width, height=height, stride=bytes_per_block, flags=flags};

    init_data: []D3D11_SUBRESOURCE_DATA;

    if data && !generate_mips {
        init_data = NewArray(data.count, D3D11_SUBRESOURCE_DATA,, temp);

        // If we are multisampled, we cannot pass initial data anyway.
        array_count := ifx flags & .Is_3D 1 else array_count_or_depth;
        for i: 0..array_count-1 {
            for j: 0..mip_levels_or_msaa-1 {
                // D3D11CalcSubresource
                index := j + i * mip_levels_or_msaa;
                block_width := cast(u32)max(1, width >> j);
                block_height:= cast(u32)max(1, height >> j);

                if is_block_compression(format) {
                    block_width  = (block_width + 3) / 4;
                    block_height = (block_height + 3) / 4;
                }

                pitch := block_width * bytes_per_block;
                init_data[index] = D3D11_SUBRESOURCE_DATA.{
                    pSysMem = data[index],
                    SysMemPitch = pitch,
                    SysMemSlicePitch = pitch * block_height,
                };
            }
        }
    }

    if flags & .Is_3D {
        if flags & .Multisample {
            log_error("[Gaco] Error while creating texture: .Multisample cannot be mixed with .Is_3D.");
            return .{};
        }

        desc := D3D11_TEXTURE3D_DESC.{
            Width = width,
            Height = height,
            Depth = array_count_or_depth,
            MipLevels = mip_levels_or_msaa,
            Format = d3d11_format,
            BindFlags = bind_flags,
            MiscFlags = misc_flags,
            Usage = usage,
            CPUAccessFlags = access_flags,
        };

        hr := ID3D11Device_CreateTexture3D(device, *desc, init_data.data, *texture.texture3d);
        check_hr("ID3D11Device.CreateTexture3D", #code return .{});
    }
    else {
        mip_levels: u32 = 1;
        msaa: u32 = 1;
        if flags & .Multisample {
            msaa = mip_levels_or_msaa;
        }
        else {
            mip_levels = mip_levels_or_msaa;
        }

        desc := D3D11_TEXTURE2D_DESC.{
            Width = width,
            Height = height,
            SampleDesc.Count = msaa,
            MipLevels = mip_levels,
            ArraySize = array_count_or_depth,
            Format = d3d11_format,
            BindFlags = bind_flags,
            MiscFlags = misc_flags,
            Usage = usage,
            CPUAccessFlags = access_flags,
        };

        hr := ID3D11Device_CreateTexture2D(device, *desc, init_data.data, *texture.texture2d);
        check_hr("ID3D11Device.CreateTexture2D", #code return .{});
    }

    resource := ifx flags & .Is_3D cast(*ID3D11Resource) texture.texture3d else texture.texture2d;

    if generate_mips {
        for data {
            // D3D11CalcSubresource
            index := mip_levels_or_msaa * cast(u32)it_index;
            block_width := width;
            block_height := height;
            if is_block_compression(format) {
                block_width  = cast(u32)max(1, (block_width + 3) / 4);
                block_height = cast(u32)max(1, (block_height + 3) / 4);
            }
            pitch := block_width * bytes_per_block;
            ID3D11DeviceContext_UpdateSubresource(device_context, resource, index, null, it, pitch, pitch * block_height);
        }
    }

    // Create the view

    // TODO(Yasin): We do not handle arrays right now, which is not good
    if bind_flags & .SHADER_RESOURCE {
        hr := ID3D11Device_CreateShaderResourceView(device, resource, null, *texture.resource_view);
        check_hr("ID3D11Device.CreateShaderResourceView", #code return .{});

        if generate_mips {
            ID3D11DeviceContext_GenerateMips(device_context, texture.resource_view);
        }
    }
    else if bind_flags & .UNORDERED_ACCESS {
        hr := ID3D11Device_CreateUnorderedAccessView(device, resource, null, * texture.unordered_access_view);
        check_hr("ID3D11Device.CreateUnorderedAccessView", #code return .{});

    }

    return texture;
}

bind_texture :: (texture: Texture, slot: u32) {
    if texture.flags & .Compute_RW {
        ID3D11DeviceContext_CSSetUnorderedAccessViews(device_context, slot, 1, *texture.unordered_access_view, null);
    }
    else {
        ID3D11DeviceContext_VSSetShaderResources(device_context, slot, 1, *texture.resource_view);
        ID3D11DeviceContext_PSSetShaderResources(device_context, slot, 1, *texture.resource_view);
        if shader_state & .Compute
            ID3D11DeviceContext_CSSetShaderResources(device_context, slot, 1, *texture.resource_view);
    }
}

copy_texture :: (from: Texture, to: *Texture) {
    ID3D11DeviceContext_CopyResource(device_context, to.texture2d, from.texture2d);
}

// @Incomplete: subresource
copy_texture :: (from: Texture, to: *Texture, source_rect: Rect) {
    box := box_from_rect(source_rect);
    ID3D11DeviceContext_CopySubresourceRegion(device_context, to.texture2d, 0, 0, 0, 0, from.texture2d, 0, *box);
}

copy_texture :: (from: Texture, to: *Texture, source_box: Box) {
    box := box_from_box(source_box);
    ID3D11DeviceContext_CopySubresourceRegion(device_context, to.texture3d, 0, 0, 0, 0, from.texture3d, 0, *box);
}

// NOTE(Yasin): This doesn't support copying the depth stencil buffer.
copy_from_render_target :: (render_target: Render_Target, to: *Texture, index: u32 = 0) {
    resource: *ID3D11Resource;
    ID3D11View_GetResource(render_target.color_views[index], *resource);
    tex: *ID3D11Texture2D;
    hr := IUnknown_QueryInterface(resource, *uid(ID3D11Texture2D_UUID), cast(**void)*tex);
    check_hr("IUnknown.QueryInterface");
    IUnknown_Release(resource);

    desc: D3D11_TEXTURE2D_DESC;
    ID3D11Texture2D_GetDesc(tex, *desc);

    if desc.SampleDesc.Count > 1 { // Multisampled
        temp_desc := desc;
        temp_desc.SampleDesc = .{1, 0};
        temp_tex: *ID3D11Texture2D;
        ID3D11Device_CreateTexture2D(device, *temp_desc, null, *temp_tex);

        ID3D11DeviceContext_ResolveSubresource(device_context, temp_tex, 0, tex, 0, desc.Format);
        ID3D11DeviceContext_CopyResource(device_context, to.texture2d, temp_tex);
        IUnknown_Release(temp_tex);
    }
    else {
        ID3D11DeviceContext_CopyResource(device_context, to.texture2d, tex);
    }
}

// @Incomplete: give more options
create_sampler :: (filtering := Sampler_Filtering.Linear, edge_handling := Sampler_Edge_Handling.Clamp, max_anisotropy: u32 = 1, comparison := false) -> Sampler {
    d3d11_filter: D3D11_FILTER;
    if max_anisotropy > 1 {
        // We override the filter, there is no such requirement in OpenGL.
        d3d11_filter = .ANISOTROPIC;
    }
    else {
        FILTER_TABLE :: D3D11_FILTER.[.MIN_MAG_MIP_LINEAR, .MIN_MAG_MIP_POINT];
        d3d11_filter = FILTER_TABLE[filtering];
    }
    ADDRESS_MODE_TABLE :: D3D11_TEXTURE_ADDRESS_MODE.[.WRAP, .MIRROR, .CLAMP, .BORDER];
    address_mode := ADDRESS_MODE_TABLE[edge_handling];

    if comparison {
        // Comparison and non-comparison filters are 0x80 apart.
        d3d11_filter += 0x80;
    }

    sampler_desc := D3D11_SAMPLER_DESC.{
        Filter = d3d11_filter,
        AddressU = address_mode, AddressV = address_mode, AddressW = address_mode,
        MaxAnisotropy = max_anisotropy,
        ComparisonFunc = .NEVER, // @Incomplete
        MinLOD = 0,
        MaxLOD = cast(float32)D3D11_FLOAT32_MAX,
    };

    sampler: Sampler;
    hr := ID3D11Device_CreateSamplerState(device, *sampler_desc,*sampler.state);
    check_hr("ID3D11Device.CreateSamplerState", #code `return .{});
    return sampler;
}

bind_sampler :: (sampler: Sampler, slot: u32) {
    ID3D11DeviceContext_VSSetSamplers(device_context, slot, 1, *sampler.state);
    ID3D11DeviceContext_PSSetSamplers(device_context, slot, 1, *sampler.state);
    if shader_state & .Compute
        ID3D11DeviceContext_CSSetSamplers(device_context, slot, 1, *sampler.state);
}

destroy_sampler :: (sampler: *Sampler) {
    safe_release_and_reset(*sampler.state);
}

#scope_module
VS_EXTENSION :: ".dxvs";
FS_EXTENSION :: ".dxfs";
CS_EXTENSION :: ".dxcs";

#scope_file
using D3D11_State: struct {
    device: *ID3D11Device;
    device_context: *ID3D11DeviceContext;
    swap_chain: *IDXGISwapChain1;

    window_render_target: Render_Target;
    // bound_render_target: *Render_Target;

    rasterizer_modes: [#run enum_count(Rasterizer_Mode)]*ID3D11RasterizerState;
    blend_modes: [#run enum_count(Blend_Mode)]*ID3D11BlendState;

    // TODO(Yasin): Experiment more with stencil buffers to figure out the best options here.
    depth_stencil_modes: [#run enum_count(Depth_Stencil_Mode)]*ID3D11DepthStencilState;
    msaa: u32;

    shader_state: Shader_Type; // Currently bound shaders.
}

box_from_rect :: inline (rect: Rect) -> D3D11_BOX {
    box: D3D11_BOX;
    box.left = xx rect.x;
    box.top = xx rect.y;
    box.right = xx (rect.x + rect.width);
    box.bottom = xx (rect.y + rect.height);
    box.back = 1;
    return box;
}

box_from_box :: inline (box: Box) -> D3D11_BOX {
    d_box: D3D11_BOX;
    d_box.left = xx box.x;
    d_box.top = xx box.y;
    d_box.front = xx box.z;
    d_box.right = xx (box.x + box.width);
    d_box.bottom = xx (box.y + box.height);
    d_box.back = xx (box.z + box.depth);
    return d_box;
}

init_preloaded_modes :: () {
    ds_desc := D3D11_DEPTH_STENCIL_DESC.{
        DepthEnable = .TRUE,
        DepthWriteMask = .ALL,
        DepthFunc = .LESS_EQUAL,
        StencilEnable = .TRUE,

        StencilReadMask = D3D11_DEFAULT_STENCIL_READ_MASK,
        StencilWriteMask = D3D11_DEFAULT_STENCIL_WRITE_MASK,

        FrontFace.StencilFunc = .ALWAYS,
        FrontFace.StencilFailOp = .KEEP,
        FrontFace.StencilDepthFailOp = .KEEP,
        FrontFace.StencilPassOp = .KEEP,

        BackFace.StencilFunc = .ALWAYS,
        BackFace.StencilFailOp = .KEEP,
        BackFace.StencilDepthFailOp = .KEEP,
        BackFace.StencilPassOp = .KEEP,
    };
    {
        using Depth_Stencil_Mode;
        ID3D11Device_CreateDepthStencilState(device, *ds_desc, *depth_stencil_modes[Depth_Stencil]);

        ds_desc.DepthFunc = .GREATER_EQUAL;
        ID3D11Device_CreateDepthStencilState(device, *ds_desc, *depth_stencil_modes[Depth_Reversed]);
        ds_desc.DepthFunc = .LESS_EQUAL;

        ds_desc.DepthWriteMask = .ZERO;
        ID3D11Device_CreateDepthStencilState(device, *ds_desc, *depth_stencil_modes[No_Depth_Mask]);

        ds_desc.DepthEnable = .FALSE;
        ID3D11Device_CreateDepthStencilState(device, *ds_desc, *depth_stencil_modes[No_Depth]);


        ds_desc.StencilEnable = .FALSE;
        ID3D11Device_CreateDepthStencilState(device, *ds_desc, *depth_stencil_modes[No_Depth_Stencil]);

        ds_desc.DepthEnable = .TRUE;
        ds_desc.DepthWriteMask = .ALL;
        ds_desc.DepthFunc = .LESS_EQUAL;
        ID3D11Device_CreateDepthStencilState(device, *ds_desc, *depth_stencil_modes[No_Stencil]);
    }
    rs_desc := D3D11_RASTERIZER_DESC.{
        FillMode = .SOLID,
        CullMode = .BACK,
        DepthClipEnable = .TRUE,
        ScissorEnable = .TRUE,
    };
    {
        using Rasterizer_Mode;
        ID3D11Device_CreateRasterizerState(device, *rs_desc, *rasterizer_modes[Scissor]);

        rs_desc.ScissorEnable = .FALSE;
        ID3D11Device_CreateRasterizerState(device, *rs_desc, *rasterizer_modes[Default]);

        rs_desc.CullMode = .FRONT;
        ID3D11Device_CreateRasterizerState(device, *rs_desc, *rasterizer_modes[Front_Cull]);

        rs_desc.CullMode = .NONE;
        ID3D11Device_CreateRasterizerState(device, *rs_desc, *rasterizer_modes[No_Cull]);
    }
    blend_alpha_desc: D3D11_BLEND_DESC;
    blend_alpha_desc.IndependentBlendEnable = .FALSE;
    blend_alpha_desc.RenderTarget[0] = .{
        BlendEnable = .TRUE,
        SrcBlend = .SRC_ALPHA,
        DestBlend = .INV_SRC_ALPHA,
        BlendOp = .ADD,
        SrcBlendAlpha = .ONE,
        DestBlendAlpha = .ZERO,
        BlendOpAlpha = .ADD,
        RenderTargetWriteMask = xx D3D11_COLOR_WRITE_ENABLE.ALL,
    };
    {
        using Blend_Mode;
        ID3D11Device_CreateBlendState(device, *blend_alpha_desc, *blend_modes[Alpha]);

        // blend_modes[None] = null;
    }
}

get_input_layout_from_bytecode :: (bytecode: string) -> *ID3D11InputLayout {
    reflector: *ID3D11ShaderReflection;
    defer safe_release(reflector);

    hr := D3DReflect(bytecode.data, xx bytecode.count, *uid(ID3D11ShaderReflection_UUID), cast(**void)*reflector);
    check_hr("D3DReflect", #code `return null);

    shader_desc: D3D11_SHADER_DESC;
    ID3D11ShaderReflection_GetDesc(reflector, *shader_desc);

    input_layout: *ID3D11InputLayout;
    input_layout_desc: [..]D3D11_INPUT_ELEMENT_DESC;
    input_layout_desc.allocator = temp;

    for 0..shader_desc.InputParameters-1 {
        using param_desc: D3D11_SIGNATURE_PARAMETER_DESC;
        hr := ID3D11ShaderReflection_GetInputParameterDesc(reflector, it, *param_desc);
        check_hr("ID3D11ShaderReflection.GetInputParameterDesc", #code `return null);

        element_desc: D3D11_INPUT_ELEMENT_DESC;
        element_desc.SemanticName = SemanticName;
        element_desc.SemanticIndex = SemanticIndex;
        element_desc.AlignedByteOffset = D3D11_APPEND_ALIGNED_ELEMENT;

        // @Document: How instance parameters are passed.
        // Instance data is passed to the slot 1 (in bind_buffer) and vertex data to the slot 0.
        is_instance, step_rate := get_semantic_info(to_string(SemanticName));
        element_desc.InstanceDataStepRate = step_rate;

        if is_instance {
            element_desc.InputSlot = 1;
            element_desc.InputSlotClass = .INSTANCE_DATA;
        }
        else {
            element_desc.InputSlot = 0;
            element_desc.InputSlotClass = .VERTEX_DATA;
        }

        // determine DXGI format
        if Mask == 1
        {
            if ComponentType == {
            case .REGISTER_COMPONENT_UINT32;
                element_desc.Format = .R32_UINT;
            case .REGISTER_COMPONENT_SINT32;
                element_desc.Format = .R32_SINT;
            case .REGISTER_COMPONENT_FLOAT32;
                element_desc.Format = .R32_FLOAT;
            }
        }
        else if Mask <= 3
        {
            if ComponentType == {
                case .REGISTER_COMPONENT_UINT32; element_desc.Format = .R32G32_UINT;
                case .REGISTER_COMPONENT_SINT32; element_desc.Format = .R32G32_SINT;
                case .REGISTER_COMPONENT_FLOAT32; element_desc.Format = .R32G32_FLOAT;
            }
        }
        else if Mask <= 7
        {
            if ComponentType == {
                case .REGISTER_COMPONENT_UINT32; element_desc.Format = .R32G32B32_UINT;
                case .REGISTER_COMPONENT_SINT32; element_desc.Format = .R32G32B32_SINT;
                case .REGISTER_COMPONENT_FLOAT32; element_desc.Format = .R32G32B32_FLOAT;
            }
        }
        else if Mask <= 15
        {
            if ComponentType ==  {
                case .REGISTER_COMPONENT_UINT32; element_desc.Format = .R32G32B32A32_UINT;
                case .REGISTER_COMPONENT_SINT32; element_desc.Format = .R32G32B32A32_SINT;
                case .REGISTER_COMPONENT_FLOAT32; element_desc.Format = .R32G32B32A32_FLOAT;
            }
        }

        array_add(*input_layout_desc, element_desc);
    }

    hr = ID3D11Device_CreateInputLayout(device, input_layout_desc.data, cast(u32) input_layout_desc.count, bytecode.data, cast(u64) bytecode.count, *input_layout);
    check_hr("ID3D11Device.CreateInputLayout", #code `return null);

    return input_layout;
}


check_hr :: (from: string, code_to_insert_after_fail := #code `return) #expand {
    if FAILED(`hr) {
        System :: #import "System";
        error_code := cast,no_check(OS_Error_Code)`hr; // We know that it is less than 0 if it's a failure. OS_Error_Code is a u32
        fail_message := System.get_error_string(error_code);

        log_error("[Gaco] % failed with code 0x%: %", from, FormatInt.{value = error_code, base=16}, fail_message);
        #if !DEBUG {
            log("Pass DEBUG=true when importing Gaco to learn more.");
        }

        #insert code_to_insert_after_fail;
    }
}

#import "d3d11";
#import "d3d_compiler";
#import "dxgi";
#import "Windows";

#if DEBUG {
    Crash_Handler :: #import "Runtime_Support_Crash_Handler";
    init_exception_handler :: () {
        info: *ID3D11InfoQueue;
        hr := IUnknown_QueryInterface(device, *uid(ID3D11InfoQueue_UUID), cast(**void) *info);
        if(SUCCEEDED(hr))
        {
            ID3D11InfoQueue_SetBreakOnSeverity(info, .CORRUPTION, 1);
            ID3D11InfoQueue_SetBreakOnSeverity(info, .ERROR, 1);

        }
        safe_release(info);
        SetUnhandledExceptionFilter(xx handle_exception);
    }

    handle_exception :: (pExceptionInfo: *Crash_Handler.EXCEPTION_POINTERS) -> s32 #c_call {
        push_context {
            msg, found := log_messages_and_get_last();
            if found {
                MessageBoxA(null, msg.data, "D3D11 Error", MB_OK | MB_ICONERROR);
            }
        }
        return Crash_Handler.handle_exception(pExceptionInfo);
    }
    log_messages_and_get_last :: () -> string, bool {
        info: *ID3D11InfoQueue;
        IUnknown_QueryInterface(device, *uid(ID3D11InfoQueue_UUID), cast(**void) *info);

        message_count := ID3D11InfoQueue_GetNumStoredMessages(info);
        if message_count == 0 return .{}, false;
        logged_ids: [..]D3D11_MESSAGE_ID;
        message_str: string;

        error := false;
        for i: 0..message_count-1 {
            message_size: u64;
            ID3D11InfoQueue_GetMessageA(info, i, null, *message_size);

            message := cast(*D3D11_MESSAGE) alloc(cast(s64)message_size,, temp);
            ID3D11InfoQueue_GetMessageA(info, i, message, *message_size);

            for logged_ids {
                if it == message.ID  continue i;
            }
            array_add(*logged_ids, message.ID);

            if message.Severity == .ERROR || message.Severity == .CORRUPTION {
                error = true;
            }

            message_str = string.{data=message.pDescription, count=xx message.DescriptionByteLength-1};
            flags := ifx error Log_Flags.ERROR else .WARNING;
            log("[Gaco] % - %\n", message.ID, message_str, flags=flags);
        }
        ID3D11InfoQueue_ClearStoredMessages(info);
        safe_release(info);
        return message_str, error;
    }
}