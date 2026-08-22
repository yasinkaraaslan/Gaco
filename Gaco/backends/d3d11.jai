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
    else #if type == .Structured_RW || type == .Indirect {
        uav: *ID3D11UnorderedAccessView;
    }
};

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
    mip_levels: u32 = 1;
    format: Texture_Format;
    flags: Texture_Flags;
};

Sampler :: struct {
    state: *ID3D11SamplerState;
}

Render_Target :: struct {
    color_views: [8]*ID3D11RenderTargetView;
    depth_stencil_view: *ID3D11DepthStencilView;
}

Timer :: struct {
    disjoint_query: *ID3D11Query;
    start_query:    *ID3D11Query;
    end_query:      *ID3D11Query;
    recording: bool;
}

is_valid :: (texture: Texture) -> bool {
    return texture.texture2d != null; // and texture3d
}

is_valid ::(sampler: Sampler) -> bool {
    return sampler.state != null;
}

is_valid :: (buffer: Buffer) -> bool {
    return buffer.buffer != null;
}

is_valid :: (using shader: Shader) -> bool {
    empty_vs := type & .Vertex   && (!vertex_shader || !input_layout);
    empty_fs := type & .Fragment && !fragment_shader;
    empty_cs := type & .Compute  && !compute_shader;

    return type != .Unspecified && !empty_vs && !empty_fs && !empty_cs;
}

is_valid :: (using render_target: Render_Target) -> bool {
    // If the first one is null then the color view is empty
    return color_views[0] || depth_stencil_view;
}

is_valid :: (using timer: Timer) -> bool {
    return disjoint_query != null && start_query != null && end_query != null;
}

init :: (window: Window_Type) {
    flags: D3D11_CREATE_DEVICE_FLAG;
    #if DEBUG flags |= .DEBUG;
    feature_levels := D3D_FEATURE_LEVEL.[._11_1];

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
        BufferCount = 2,
        BufferUsage = .RENDER_TARGET_OUTPUT,
        SampleDesc = .{Count = 1, Quality = 0},
        SwapEffect = .FLIP_DISCARD,
        Flags = xx DXGI_SWAP_CHAIN_FLAG.ALLOW_TEARING
    };

    dxgi_factory: *IDXGIFactory2;

    {
        dxgi_device: *IDXGIDevice2;
        hr = IUnknown_QueryInterface(device, *uid(IDXGIDevice2_UUID), xx *dxgi_device);
        check_hr("IUnknown.QueryInterface");
        defer safe_release(dxgi_device);

        dxgi_adapter: *IDXGIAdapter;
        hr = IDXGIDevice_GetAdapter(dxgi_device, *dxgi_adapter);
        check_hr("IDXGIDevice.GetAdapter");
        defer safe_release(dxgi_adapter);

        #if DEBUG {
            desc: DXGI_ADAPTER_DESC ;
            IDXGIAdapter_GetDesc(dxgi_adapter, *desc);
            renderer_name, success := wide_to_utf8(cast(*u16)desc.Description.data);
            log("[Gaco] D3D11 Renderer: %", renderer_name);
        }

        hr = IDXGIObject_GetParent(dxgi_adapter, *uid(IDXGIFactory2_UUID), xx *dxgi_factory);
        check_hr("IDXGIObject.GetParent");
    }

    hr = IDXGIFactory2_CreateSwapChainForHwnd(dxgi_factory, device, window, *swap_chain_desc, null, null, *swap_chain);
    check_hr("IDXGIFactory2.CreateSwapChainForHwnd");

    hr = IDXGIFactory_MakeWindowAssociation(dxgi_factory, window, xx DXGI_MWA.NO_ALT_ENTER);
    check_hr("IDXGIFactory.MakeWindowAssociation");
    safe_release(dxgi_factory);

    set_primitive_type(.Triangle_List);
    set_depth_stencil_state(.{});

    // NOTE(Yasin): It's safe if this fails on older systems,
    hr = IUnknown_QueryInterface(device_context, *uid(ID3DUserDefinedAnnotation_UUID), xx *annotation);
}

deinit :: () {
    #if DEBUG
        log_messages_and_get_last();

    for * state, desc: rasterizer_table
        safe_release_and_reset(state);
    for * state, desc: blend_table
        safe_release_and_reset(state);
    for * state, desc: depth_stencil_table
        safe_release_and_reset(state);

    destroy_render_target(*window_render_target);
    safe_release_and_reset(*swap_chain);
    safe_release_and_reset(*device_context);
    safe_release_and_reset(*device);
    safe_release_and_reset(*annotation);
}

create_buffer :: (data: *void, count: u32, stride: u32, $type: Buffer_Type, usage := Buffer_Usage.Default, debug_name := "") -> Buffer(type) {
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
    case .Structured_RW;
        bd.BindFlags = .UNORDERED_ACCESS;
        bd.MiscFlags = .BUFFER_STRUCTURED;
        bd.StructureByteStride = stride;
    case .Copy;
        bd.Usage = .STAGING;
        bd.CPUAccessFlags |= .READ;
    case .Indirect;
        bd.BindFlags = .UNORDERED_ACCESS;
        bd.MiscFlags = .DRAWINDIRECT_ARGS | .BUFFER_ALLOW_RAW_VIEWS;
    }

    init_data: *D3D11_SUBRESOURCE_DATA = null;
    if data != null {
        init_data = * (D3D11_SUBRESOURCE_DATA.{
            pSysMem = data
        });
    }

    hr := ID3D11Device_CreateBuffer(device, *bd, init_data, *buffer.buffer);
    check_hr("ID3D11Device.CreateBuffer", #code `return .{});
    if debug_name  d3d11_set_debug_name(buffer.buffer, debug_name);

    #if type == .Structured {
        srv_desc := D3D11_SHADER_RESOURCE_VIEW_DESC.{
            ViewDimension = .BUFFER,
            Buffer.NumElements = count
        };
        hr = ID3D11Device_CreateShaderResourceView(device, buffer.buffer, *srv_desc, *buffer.srv);
        check_hr("ID3D11Device.CreateShaderResourceView", #code `return .{});

        if debug_name  d3d11_set_debug_name(buffer.srv, debug_name);
    }
    else #if type == .Structured_RW || type == .Indirect {
        uav_desc := D3D11_UNORDERED_ACCESS_VIEW_DESC.{
            ViewDimension = .BUFFER,
            Buffer.NumElements = count
        };
        #if type == .Indirect {
            uav_desc.Format = .R32_TYPELESS;
            uav_desc.Buffer.NumElements = stride / 4;
            uav_desc.Buffer.Flags = xx D3D11_BUFFER_UAV_FLAG.RAW;
        }

        hr = ID3D11Device_CreateUnorderedAccessView(device, buffer.buffer, *uav_desc, *buffer.uav);
        check_hr("ID3D11Device.CreateUnorderedAccessView", #code `return .{});
        if debug_name  d3d11_set_debug_name(buffer.uav, debug_name);
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

bind_buffer :: (buffer: Buffer(.Constant), slot: u32 = 0, bind_to: Shader_Type) {
    if bind_to & .Vertex
        ID3D11DeviceContext_VSSetConstantBuffers(device_context, slot, 1, *buffer.buffer);
    if bind_to & .Fragment
        ID3D11DeviceContext_PSSetConstantBuffers(device_context, slot, 1, *buffer.buffer);
    if bind_to & .Compute
        ID3D11DeviceContext_CSSetConstantBuffers(device_context, slot, 1, *buffer.buffer);
}

bind_buffer :: (buffer: Buffer(.Structured), slot: u32 = 0, bind_to: Shader_Type) {
    if bind_to & .Vertex
        ID3D11DeviceContext_VSSetShaderResources(device_context, slot, 1, *buffer.srv);
    if bind_to & .Fragment
        ID3D11DeviceContext_PSSetShaderResources(device_context, slot, 1, *buffer.srv);
    if bind_to & .Compute
        ID3D11DeviceContext_CSSetShaderResources(device_context, slot, 1, *buffer.srv);
}

// TODO(Yasin): OMSetRenderTargetsAndUnorderedAccessViews
// Note that these need to be unbound when drawing indirect so... we'll have to come up with something.
bind_buffer :: (buffer: Buffer(.Structured_RW), slot: u32 = 0) {
    ID3D11DeviceContext_CSSetUnorderedAccessViews(device_context, slot, 1, *buffer.uav, null);
}

// Same as above
bind_buffer :: (buffer: Buffer(.Indirect), slot: u32 = 0) {
    ID3D11DeviceContext_CSSetUnorderedAccessViews(device_context, slot, 1, *buffer.uav, null);
}

// You can ignore 'busy' if you didn't specify .Non_Blocking
map_buffer :: (buffer: *Buffer, flags: Map_Flags) -> *void, busy: bool {
    data, busy := d3d11_map_resource(buffer.buffer, flags, buffer.type == .Copy, 0);
    return data, busy;
}

unmap_buffer :: (buffer: *Buffer) {
    ID3D11DeviceContext_Unmap(device_context, buffer.buffer, 0);
}

// You can ignore 'busy' if you didn't specify .Non_Blocking
map_texture :: (texture: *Texture, flags: Map_Flags) -> *void, busy: bool {
    assert(texture.flags & .Copy != 0, "[Gaco] Only Copy textures can be mapped to read.");
    data, busy := d3d11_map_resource(texture.texture2d, flags, true, 0);
    return data, busy;
}

unmap_texture :: (texture: *Texture) {
    ID3D11DeviceContext_Unmap(device_context, texture.texture2d, 0);
}

update_buffer :: (buffer: *Buffer, data: *void) {
    ID3D11DeviceContext_UpdateSubresource(device_context, buffer.buffer, 0, null, data, 0, 0);
}

update_texture :: (texture: *Texture, data: *void, rect: Rect, subresource: u32 = 0) {
    row := cast(u32)rect.width * texture.stride;
    box := box_from_rect(rect);
    ID3D11DeviceContext_UpdateSubresource(device_context, texture.texture2d, subresource, *box, data, row, 0);
}

update_texture :: (texture: *Texture, data: *void, box: Box, subresource: u32 = 0) {
    row := cast(u32)box.width * texture.stride;
    d_box := box_from_box(box);
    ID3D11DeviceContext_UpdateSubresource(device_context, texture.texture3d, subresource, *d_box, data, row, row * box.height.(u32));

}

update_texture :: (using texture: *Texture, data: *void, subresource: u32 = 0) {
    row := width * stride;
    ID3D11DeviceContext_UpdateSubresource(device_context, texture2d, subresource, null, data, row, row * height);
}

write_buffer :: (buffer: *Buffer, data: *void, size: int) {
    subresource: D3D11_MAPPED_SUBRESOURCE;
    hr := ID3D11DeviceContext_Map(device_context, buffer.buffer, 0, .WRITE_DISCARD, 0, *subresource);
    check_hr("ID3D11DeviceContext.Map", #code return);
    memcpy(subresource.pData, data, size);
    ID3D11DeviceContext_Unmap(device_context, buffer.buffer, 0);
}

copy_buffer :: (from: Buffer, to: *Buffer) {
    ID3D11DeviceContext_CopyResource(device_context, to.buffer, from.buffer);
}

destroy_buffer :: (buffer: *Buffer) {
    safe_release_and_reset(*buffer.buffer);

    #if buffer.type == .Structured   {
        safe_release_and_reset(*buffer.srv);
    }
    else #if buffer.type == .Structured_RW || buffer.type == .Indirect {
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

compile_shader_to_bytecode :: (source: string, type: Shader_Type, file_name: string, defines := string.[]) -> Shader_Bytecode, bool {
    bytecode: Shader_Bytecode;
    flags := D3DCOMPILE.ENABLE_STRICTNESS;

    #if DEBUG {
        flags |= .DEBUG | .SKIP_OPTIMIZATION | .WARNINGS_ARE_ERRORS;
    }

    compile :: (entry_point: string, target: string) -> string #expand {
        output, errors, hr := D3DCompile(source, file_name, defines, D3D_COMPILE_STANDARD_FILE_INCLUDE, entry_point, target, xx flags, 0);
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

load_shader_from_bytecode :: (bytecode: Shader_Bytecode, type: Shader_Type, debug_name := "") -> Shader {
    shader: Shader;
    if type & .Vertex {
        hr := ID3D11Device_CreateVertexShader(device, bytecode.vs.data, xx bytecode.vs.count, null, *shader.vertex_shader);
        check_hr("ID3D11Device.CreateVertexShader", #code `return .{});

        shader.input_layout = get_input_layout_from_bytecode(bytecode.vs);
        if debug_name {
            d3d11_set_debug_name(shader.input_layout, debug_name);
            d3d11_set_debug_name(shader.vertex_shader, debug_name);
        }
    }

    if type & .Fragment {
        hr := ID3D11Device_CreatePixelShader(device, bytecode.fs.data, xx bytecode.fs.count, null, *shader.fragment_shader);
        check_hr("ID3D11Device.CreatePixelShader", #code `return .{});
        if debug_name
            d3d11_set_debug_name(shader.fragment_shader, debug_name);
    }

    if type & .Compute {
        hr := ID3D11Device_CreateComputeShader(device, bytecode.cs.data, xx bytecode.cs.count, null, *shader.compute_shader);
        check_hr("ID3D11Device.CreateComputeShader", #code `return .{});
        if debug_name
            d3d11_set_debug_name(shader.compute_shader, debug_name);
    }


    shader.type = type;
    return shader;
}

clear :: (render_target: Render_Target, color: Vector4, depth := 1.0, stencil: u8 = 0, $flags: Clear_Flags = .Color | .Depth | .Stencil) {
    #if flags & .Color {
        for render_target.color_views {
            if it  ID3D11DeviceContext_ClearRenderTargetView(device_context, it, *color.component);
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

clear :: inline (color: Vector4, depth := 1.0, stencil: u8 = 0, $flags: Clear_Flags = .Color | .Depth | .Stencil) {
    clear(custom_render_target, color, depth, stencil, flags);
}

set_shader :: (shader: Shader) {
    if shader.type & .Vertex {
        ID3D11DeviceContext_IASetInputLayout(device_context, shader.input_layout);
        ID3D11DeviceContext_VSSetShader(device_context, shader.vertex_shader, null, 0);
    }
    if shader.type & .Fragment {
        ID3D11DeviceContext_PSSetShader(device_context, shader.fragment_shader, null, 0);
    }
    if shader.type & .Compute {
        ID3D11DeviceContext_CSSetShader(device_context, shader.compute_shader, null, 0);
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
set_viewport :: (info: Viewport_Desc) {
    viewport := cast,force(D3D11_VIEWPORT)info;
    ID3D11DeviceContext_RSSetViewports(device_context, 1, *viewport);
}

get_viewport :: () -> Viewport_Desc {
    info: Viewport_Desc;
    count : u32 = 1;
    ID3D11DeviceContext_RSGetViewports(device_context, *count, *cast,force(D3D11_VIEWPORT)info);
    return info;
}

set_rasterizer_state :: (desc: Rasterizer_Desc) {
    found, state := table_find(*rasterizer_table, desc);

    if !found {
        rasterizer_desc := D3D11_RASTERIZER_DESC.{
            FillMode              = cast(D3D11_FILL_MODE) desc.fill_mode,
            CullMode              = cast(D3D11_CULL_MODE) desc.cull_mode,
            FrontCounterClockwise = xx desc.front_counter_clockwise,
            DepthBias             = desc.depth_bias,
            DepthBiasClamp        = desc.depth_bias_clamp,
            SlopeScaledDepthBias  = desc.slope_scaled_depth_bias,
            DepthClipEnable       = xx desc.depth_clip_enable,
            ScissorEnable         = xx desc.scissor_enable,
            MultisampleEnable     = .TRUE, // https://learn.microsoft.com/en-us/windows/win32/api/d3d11/ns-d3d11-d3d11_rasterizer_desc
            AntialiasedLineEnable = xx desc.antialiased_line_enable,
        };

        hr := ID3D11Device_CreateRasterizerState(device, *rasterizer_desc, *state);
        table_add(*rasterizer_table, desc, state);
    }

    // 'device_context' is your ID3D11DeviceContext
    ID3D11DeviceContext_RSSetState(device_context, state);
}

// More info about alpha to coverage
// https://learn.microsoft.com/en-us/windows/win32/direct3d11/d3d10-graphics-programming-guide-blend-state#alpha-to-coverage
set_blend_state :: (desc: Blend_Desc, alpha_to_coverage_enable := false, blend_factor := Vector4.{}, sample_mask: u32 = 0xFFFF_FFFF) {
    d3d11_set_blend(.[desc], alpha_to_coverage_enable, blend_factor, sample_mask, false);
}

// If you want to set them independently
set_blend_state :: (descs: []Blend_Desc, alpha_to_coverage_enable := false, blend_factor := Vector4.{}, sample_mask: u32 = 0xFFFF_FFFF) {
    d3d11_set_blend(descs, alpha_to_coverage_enable, blend_factor, sample_mask, true);
}

set_depth_stencil_state :: (desc: Depth_Stencil_Desc, stencil_ref: u8 = 0xFF) {
    found, state := table_find(*depth_stencil_table, desc);
    if !found {
        front := desc.front_face;
        back := desc.back_face;

        // Same enum values for all
        d3d11_desc := D3D11_DEPTH_STENCIL_DESC.{
            DepthEnable                  = xx desc.depth_enable,
            DepthWriteMask               = xx desc.depth_write,
            DepthFunc                    = xx desc.depth_func,
            StencilEnable                = xx desc.stencil_enable,

            StencilReadMask              = desc.stencil_read_mask,
            StencilWriteMask             = desc.stencil_write_mask,

            FrontFace.StencilFunc        = xx front.compare_op,
            FrontFace.StencilFailOp      = xx front.fail_op,
            FrontFace.StencilDepthFailOp = xx front.depth_fail_op,
            FrontFace.StencilPassOp      = xx front.pass_op,

            BackFace.StencilFunc         = xx back.compare_op,
            BackFace.StencilFailOp       = xx back.fail_op,
            BackFace.StencilDepthFailOp  = xx back.depth_fail_op,
            BackFace.StencilPassOp       = xx back.pass_op,
        };
        ID3D11Device_CreateDepthStencilState(device, *d3d11_desc, *state);
        table_add(*depth_stencil_table, desc, state);
    }
    ID3D11DeviceContext_OMSetDepthStencilState(device_context, state, stencil_ref);
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

draw_indirect :: ($indexed: bool, buffer: Buffer(.Indirect), byte_offset: u32 = 0) {
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

dispatch_compute_indirect :: (buffer: Buffer(.Indirect), byte_offset: u32 = 0) {
    ID3D11DeviceContext_DispatchIndirect(device_context, buffer.buffer, byte_offset);
}

present :: (interval: u32 = 1) {
    back_buffer: *ID3D11Texture2D;
    ID3D11View_GetResource(window_render_target.color_views[0], xx *back_buffer);
    ID3D11DeviceContext_ResolveSubresource(
        device_context,
        back_buffer, 0,
        custom_color_texture.texture2d, 0,  // Source (multisampled offscreen target)
        DXGI_FORMAT_MAP[custom_color_texture.format]
    );
    IUnknown_Release(back_buffer);

    present_flags: DXGI_PRESENT;
    if interval == 0 {
        present_flags |= .ALLOW_TEARING;
    }

    hr := IDXGISwapChain_Present(swap_chain, interval, xx present_flags);
    check_hr("IDXGISwapChain_Present", #code {});
}

// NOTE(Yasin): You cannot currently create 3d textures or texture arrays for render targets, but to
// write to them you need geometry shaders, which we don't support anyways.
create_render_target :: (color_textures: []Texture, depth_stencil_texture: Texture, debug_name := "") -> Render_Target {
    render_target: Render_Target;
    if color_textures {
        for color_textures {
            hr := ID3D11Device_CreateRenderTargetView(device, it.texture2d, null, *render_target.color_views[it_index]);
            check_hr("ID3D11Device.CreateRenderTargetView", #code return .{});
            if debug_name  d3d11_set_debug_name(render_target.color_views[it_index], debug_name);
        }
    }

    if is_valid(depth_stencil_texture) {
        ds_desc: D3D11_DEPTH_STENCIL_VIEW_DESC;
        ds_desc.Format = DXGI_FORMAT_MAP[depth_stencil_texture.format];
        if depth_stencil_texture.flags & .Multisample {
            ds_desc.ViewDimension = .D3D11_DSV_DIMENSION_TEXTURE2DMS;
        }
        else {
            ds_desc.ViewDimension = .D3D11_DSV_DIMENSION_TEXTURE2D;
            ds_desc.Texture2D.MipSlice = 0;
        }
        hr := ID3D11Device_CreateDepthStencilView(device, depth_stencil_texture.texture2d, *ds_desc, *render_target.depth_stencil_view);
        check_hr("ID3D11Device.CreateDepthStencilView", #code return .{});
        if debug_name  d3d11_set_debug_name(render_target.depth_stencil_view, debug_name);

    }
    return render_target;
}

set_render_target :: (using render_target: Render_Target) {
    ID3D11DeviceContext_OMSetRenderTargets(device_context, xx color_views.count, color_views.data, depth_stencil_view);
}

destroy_render_target :: (render_target: *Render_Target) {
    for * render_target.color_views {
        safe_release_and_reset(it);
    }
    safe_release_and_reset(*render_target.depth_stencil_view);
}

resize :: (width: int, height: int, msaa: u32 = 4, color_format := Texture_Format.RGBA8, depth_format := Texture_Format.D24S8) -> render_target: Render_Target {
    destroy_render_target(*window_render_target);
    destroy_render_target(*custom_render_target);
    destroy_texture(*custom_color_texture);
    destroy_texture(*custom_depth_texture);

    set_render_target(.{});

    hr := IDXGISwapChain_ResizeBuffers(swap_chain, 0, cast(u32)width, cast(u32)height, .UNKNOWN, xx DXGI_SWAP_CHAIN_FLAG.ALLOW_TEARING);
    check_hr("IDXGISwapChain.ResizeBuffers", #code `return .{});

    back_buffer: Texture;
    hr = IDXGISwapChain_GetBuffer(swap_chain, 0, *uid(ID3D11Texture2D_UUID), xx *back_buffer.texture2d);
    check_hr("IDXGISwapChain.GetBuffer", #code `return .{});
    defer destroy_texture(*back_buffer);

    window_render_target = create_render_target(.[back_buffer], .{});

    custom_color_texture = create_texture(.[], cast(u32)width, cast(u32)height, 1, msaa, color_format, .Render_Target | .Multisample);
    custom_depth_texture = create_texture(.[], cast(u32)width, cast(u32)height, 1, msaa, depth_format, .Multisample);
    custom_render_target = create_render_target(.[custom_color_texture], custom_depth_texture);

    set_render_target(custom_render_target);
    set_viewport(.{width=xx width, height= xx height});

    return custom_render_target;
}

// Data is an array for texture arrays and mipmapping.
// Index = mip slice + (array slice * mip levels)
// Image 0 mip data | Image 1 mip data | ...
create_texture :: (data: []*u8, width: u32, height: u32, array_count_or_depth: u32 = 1, mip_levels_or_msaa: u32 = 1, format := Texture_Format.RGBA8, flags := Texture_Flags.Sampled, debug_name := "") -> Texture {
    generate_mips := (flags & .Generate_Mips) && mip_levels_or_msaa != 1;
    depth_stencil := format >= .D16 && format <= .D32FS8;

    bind_flags: D3D11_BIND_FLAG;
    misc_flags: D3D11_RESOURCE_MISC_FLAG;

    usage := D3D11_USAGE.DEFAULT;
    access_flags: D3D11_CPU_ACCESS_FLAG;

    dxgi_format := DXGI_FORMAT_MAP[format];
    srv_format := dxgi_format;

    if flags & .Copy {
        // Do not set any bind_flags for staging
        usage = .STAGING;
        access_flags |= .READ;
    } else {
        if flags & .Compute_RW {
            bind_flags |= .UNORDERED_ACCESS;
        }
        if flags & .Render_Target {
            bind_flags |= .RENDER_TARGET;
        }
        if depth_stencil {
            bind_flags |= .DEPTH_STENCIL;
        }
        if flags & .Sampled {
            bind_flags |= .SHADER_RESOURCE;
            if depth_stencil {
                dxgi_format, srv_format = get_depth_format_variants(format);
            }
        }
        if generate_mips {
            // @Speed: We would probably want to create a seperate render target texture
            // and copy it to our newly generated texture.
            bind_flags |= .RENDER_TARGET;
            misc_flags |= .GENERATE_MIPS;
        }
    }
    if flags & .Cubemap
        misc_flags |= .TEXTURECUBE;

    if dxgi_format == .DXGI_FORMAT_UNKNOWN {
        log_error("[Gaco] Error while creating texture: Format % is Unknown or unsupported.", format);
        return .{};
    }

    bytes_per_block := TEXTURE_BYTES_PER_BLOCK[format];

    // Create the thing
    texture := Texture.{
        width=width,
        height=height,
        depth=array_count_or_depth,
        stride=bytes_per_block,
        format=format,
        flags=flags
    };

    msaa: u32 = 1;
    if flags & .Multisample {
        msaa = mip_levels_or_msaa;
    } else {
        texture.mip_levels = mip_levels_or_msaa;
    }

    if flags & .Cubemap {
        texture.depth /= 6;
    }

    init_data: []D3D11_SUBRESOURCE_DATA;
    if data && !generate_mips {
        init_data = NewArray(data.count, D3D11_SUBRESOURCE_DATA,, temp);
        array_count := ifx flags & .Is_3D 1 else array_count_or_depth;

        expected_count := array_count * texture.mip_levels;
        if data.count < expected_count {
            log_error("[Gaco] Error while creating texture: Incomplete data array. Expected count %, got %.", expected_count, data.count);
            return .{};
        }

        for i: 0..array_count-1 {
            for j: 0..texture.mip_levels-1 {
                // D3D11CalcSubresource
                index := j + i * texture.mip_levels;
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
            MipLevels = texture.mip_levels,
            Format = dxgi_format,
            BindFlags = bind_flags,
            MiscFlags = misc_flags,
            Usage = usage,
            CPUAccessFlags = access_flags,
        };

        hr := ID3D11Device_CreateTexture3D(device, *desc, init_data.data, *texture.texture3d);
        check_hr("ID3D11Device.CreateTexture3D", #code return .{});
    }
    else {
        desc := D3D11_TEXTURE2D_DESC.{
            Width = width,
            Height = height,
            SampleDesc.Count = msaa,
            MipLevels = texture.mip_levels,
            ArraySize = array_count_or_depth,
            Format = dxgi_format,
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
        mip_levels := ifx texture.mip_levels else max_mip_levels(width, height);

        for data {
            // D3D11CalcSubresource
            index := mip_levels * cast(u32)it_index;
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
    if bind_flags & .SHADER_RESOURCE {
        srv_desc: D3D11_SHADER_RESOURCE_VIEW_DESC;
        srv_desc.Format = srv_format;

        if flags & .Is_3D {
            srv_desc.ViewDimension = .D3D11_SRV_DIMENSION_TEXTURE3D;
            srv_desc.Texture3D.MipLevels = 0xFFFF_FFFF; // All mips
            srv_desc.Texture3D.MostDetailedMip = 0;
        } else if flags & .Cubemap {
            if array_count_or_depth > 6 {
                srv_desc.ViewDimension = .D3D11_SRV_DIMENSION_TEXTURECUBEARRAY;
                srv_desc.TextureCubeArray.MipLevels = 0xFFFF_FFFF;
                srv_desc.TextureCubeArray.NumCubes = texture.depth;
            } else {
                srv_desc.ViewDimension = .D3D11_SRV_DIMENSION_TEXTURECUBE;
                srv_desc.TextureCube.MipLevels = 0xFFFF_FFFF;
            }
        } else if flags & .Multisample {
            if array_count_or_depth > 1 {
                srv_desc.ViewDimension = .D3D11_SRV_DIMENSION_TEXTURE2DMSARRAY;
                srv_desc.Texture2DMSArray.ArraySize = array_count_or_depth;
            } else {
                srv_desc.ViewDimension = .D3D11_SRV_DIMENSION_TEXTURE2DMS;
            }
        } else {
            if array_count_or_depth > 1 {
                srv_desc.ViewDimension = .D3D11_SRV_DIMENSION_TEXTURE2DARRAY;
                srv_desc.Texture2DArray.ArraySize = array_count_or_depth;
                srv_desc.Texture2DArray.MipLevels = 0xFFFF_FFFF;
            } else {
                srv_desc.ViewDimension = .D3D11_SRV_DIMENSION_TEXTURE2D;
                srv_desc.Texture2D.MipLevels = 0xFFFF_FFFF;
            }
        }

        hr := ID3D11Device_CreateShaderResourceView(device, resource, *srv_desc, *texture.resource_view);
        check_hr("ID3D11Device.CreateShaderResourceView", #code return .{});

        if generate_mips {
            ID3D11DeviceContext_GenerateMips(device_context, texture.resource_view);
        }
    }
    else if bind_flags & .UNORDERED_ACCESS {
        hr := ID3D11Device_CreateUnorderedAccessView(device, resource, null, *texture.unordered_access_view);
        check_hr("ID3D11Device.CreateUnorderedAccessView", #code return .{});
    }

    if debug_name {
        d3d11_set_debug_name(texture.texture2d, debug_name);
        d3d11_set_debug_name(texture.resource_view, debug_name);
    }

    return texture;
}

bind_texture :: (texture: Texture, slot: u32, bind_to := Shader_Type.Fragment) {
    if texture.flags & .Compute_RW {
        ID3D11DeviceContext_CSSetUnorderedAccessViews(device_context, slot, 1, *texture.unordered_access_view, null);
    }
    else {
        assert(texture.flags & .Sampled != 0, "[Gaco] Texture must have Sampled flag to be bound to a shader.");
        if bind_to & .Vertex
            ID3D11DeviceContext_VSSetShaderResources(device_context, slot, 1, *texture.resource_view);
        if bind_to & .Fragment
            ID3D11DeviceContext_PSSetShaderResources(device_context, slot, 1, *texture.resource_view);
        if bind_to & .Compute
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
    defer IUnknown_Release(resource);

    tex: *ID3D11Texture2D;
    hr := IUnknown_QueryInterface(resource, *uid(ID3D11Texture2D_UUID), cast(**void)*tex);
    check_hr("IUnknown.QueryInterface");
    defer IUnknown_Release(tex);


    desc: D3D11_TEXTURE2D_DESC;
    ID3D11Texture2D_GetDesc(tex, *desc);

    if desc.SampleDesc.Count > 1 { // Multisampled
        temp_desc := desc;
        temp_desc.SampleDesc = .{1, 0};
        temp_tex: *ID3D11Texture2D;
        ID3D11Device_CreateTexture2D(device, *temp_desc, null, *temp_tex);
        defer IUnknown_Release(temp_tex);

        ID3D11DeviceContext_ResolveSubresource(device_context, temp_tex, 0, tex, 0, desc.Format);
        ID3D11DeviceContext_CopyResource(device_context, to.texture2d, temp_tex);
    }
    else {
        ID3D11DeviceContext_CopyResource(device_context, to.texture2d, tex);
    }
}

create_sampler :: (filtering := Sampler_Filtering.Linear, edge_handling := Sampler_Edge_Handling.Clamp, max_anisotropy: u32 = 1, compare_op := Compare_Op.Never, debug_name := "") -> Sampler {
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

    if compare_op != .Never {
        // Comparison and non-comparison filters are 0x80 apart.
        d3d11_filter += 0x80;
    }

    sampler_desc := D3D11_SAMPLER_DESC.{
        Filter = d3d11_filter,
        AddressU = address_mode, AddressV = address_mode, AddressW = address_mode,
        MaxAnisotropy = max_anisotropy,
        ComparisonFunc = xx compare_op, // Maps to the same enum
        MinLOD = 0,
        MaxLOD = cast(float32)D3D11_FLOAT32_MAX,
    };

    sampler: Sampler;
    hr := ID3D11Device_CreateSamplerState(device, *sampler_desc,*sampler.state);
    check_hr("ID3D11Device.CreateSamplerState", #code `return .{});

    if debug_name  d3d11_set_debug_name(sampler.state, debug_name);

    return sampler;
}

bind_sampler :: (sampler: Sampler, slot: u32, bind_to := Shader_Type.Fragment) {
    if bind_to & .Vertex
        ID3D11DeviceContext_VSSetSamplers(device_context, slot, 1, *sampler.state);
    if bind_to & .Fragment
        ID3D11DeviceContext_PSSetSamplers(device_context, slot, 1, *sampler.state);
    if bind_to & .Compute
        ID3D11DeviceContext_CSSetSamplers(device_context, slot, 1, *sampler.state);
}

destroy_sampler :: (sampler: *Sampler) {
    safe_release_and_reset(*sampler.state);
}

create_timer :: (debug_name := "") -> Timer {
    desc_disjoint := D3D11_QUERY_DESC.{ Query = .TIMESTAMP_DISJOINT };
    desc_ts       := D3D11_QUERY_DESC.{ Query = .TIMESTAMP };

    timer: Timer;
    ID3D11Device_CreateQuery(device, *desc_disjoint, *timer.disjoint_query);
    ID3D11Device_CreateQuery(device, *desc_ts, *timer.start_query);
    ID3D11Device_CreateQuery(device, *desc_ts, *timer.end_query);

    if debug_name {
        d3d11_set_debug_name(timer.disjoint_query, tprint("%_Disjoint", debug_name));
        d3d11_set_debug_name(timer.start_query, tprint("%_Start", debug_name));
        d3d11_set_debug_name(timer.end_query, tprint("%_End", debug_name));
    }
    return timer;
}

start_timer :: (timer: *Timer) {
    ID3D11DeviceContext_Begin(device_context, timer.disjoint_query);
    ID3D11DeviceContext_End(device_context, timer.start_query);
    timer.recording = true;
}

stop_timer :: (timer: *Timer) {
    ID3D11DeviceContext_End(device_context, timer.end_query);
    ID3D11DeviceContext_End(device_context, timer.disjoint_query);
}


timer_get_ms :: (timer: *Timer) -> ready: bool, float {
    if !timer.recording return true, 0.0;

    disjoint_data: D3D11_QUERY_DATA_TIMESTAMP_DISJOINT;
    start_timestamp: u64;
    end_timestamp: u64;

    if ID3D11DeviceContext_GetData(device_context, timer.disjoint_query, *disjoint_data, size_of(D3D11_QUERY_DATA_TIMESTAMP_DISJOINT), 0) != S_OK return false, 0.0;
    if ID3D11DeviceContext_GetData(device_context, timer.start_query, *start_timestamp, size_of(u64), 0) != S_OK return false, 0.0;
    if ID3D11DeviceContext_GetData(device_context, timer.end_query, *end_timestamp, size_of(u64), 0) != S_OK return false, 0.0;

    timer.recording = false;

    // If a disjoint event occurred, the reading is garbage
    if disjoint_data.Disjoint return true, 0.0;
    return true, cast(float)((end_timestamp - start_timestamp).(float64) * 1000.0 / disjoint_data.Frequency.(float64));
}

begin_debug_region :: (name: string) {
    #if DEBUG {
        if !annotation return;
        wide_name := utf8_to_wide(name,, temp);
        annotation.BeginEvent(annotation, wide_name);
    }
}

end_debug_region :: () {
    #if DEBUG {
        if !annotation return;
        annotation.EndEvent(annotation);
    }
}

insert_debug_marker :: (name: string) {
    #if DEBUG {
        if !annotation return;
        wide_name := utf8_to_wide(name,, temp);
        annotation.SetMarker(annotation, wide_name);
    }
}

// You might need these for initializing ImGui etc.
get_d3d_device :: () -> *ID3D11Device {
    return device;
}

get_d3d_device_context :: () -> *ID3D11DeviceContext {
    return device_context;
}

#scope_file
using D3D11_State: struct {
    device: *ID3D11Device;
    device_context: *ID3D11DeviceContext;
    swap_chain: *IDXGISwapChain1;

    window_render_target: Render_Target;
    custom_render_target: Render_Target;
    custom_color_texture: Texture;
    custom_depth_texture: Texture;
    // bound_render_target: *Render_Target;

    rasterizer_table: Table(Rasterizer_Desc, *ID3D11RasterizerState, get_plain_old_data_hash, compare_plain_old_data);

    // We can't use our own description because it doesn't map exactly
    blend_table: Table(D3D11_BLEND_DESC, *ID3D11BlendState, get_plain_old_data_hash, compare_plain_old_data);

    depth_stencil_table: Table(Depth_Stencil_Desc, *ID3D11DepthStencilState, get_plain_old_data_hash, compare_plain_old_data);


    annotation: *ID3DUserDefinedAnnotation;
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

get_depth_format_variants :: (format: Texture_Format) -> texture_format: DXGI_FORMAT, srv_format: DXGI_FORMAT {
   if format == {
    case .D16;
        return .R16_TYPELESS, .R16_UNORM;
    case .D24S8;
        return .R24G8_TYPELESS, .R24_UNORM_X8_TYPELESS;
    case .D32F;
        return .R32_TYPELESS, .R32_FLOAT;
    case .D32FS8;
        return .R32G8X24_TYPELESS, .R32_FLOAT_X8X24_TYPELESS;
    }
    assert(false);
    return .UNKNOWN, .UNKNOWN; // Unreachable but to shut the compiler
}

d3d11_map_resource :: inline (resource: *ID3D11Resource, flags: Map_Flags, $copy: bool, subresource_index: u32) -> *void, busy: bool {
    subresource: D3D11_MAPPED_SUBRESOURCE;
    map_type: D3D11_MAP;
    map_flags: u32 = 0;

    if flags & .Read && flags & .Write {
        map_type = .READ_WRITE;
    }
    else if flags & .Read {
        map_type = .READ;
    }
    else if flags & .Write {
        if !copy && !(flags & .Non_Blocking) {
            map_type = .WRITE_DISCARD;
        } else {
            map_type = .WRITE;
        }
    }

    // TODO(Yasin): WRITE_NO_OVERWRITE

    if flags & .Non_Blocking {
        map_flags |= xx D3D11_MAP_FLAG.DO_NOT_WAIT;
    }

    hr := ID3D11DeviceContext_Map(device_context, resource, subresource_index, map_type, map_flags, *subresource);
    if hr == DXGI_ERROR_WAS_STILL_DRAWING {
        return null, true;
    }

    check_hr("ID3D11DeviceContext.Map", #code return null, false);
    return subresource.pData, false;
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

d3d11_set_blend :: (descs: []Blend_Desc, alpha_to_coverage_enable: bool, blend_factor: Vector4, sample_mask: u32, independent_blend: bool) {
    blend_desc := D3D11_BLEND_DESC.{
        IndependentBlendEnable = xx independent_blend,
        AlphaToCoverageEnable = xx alpha_to_coverage_enable,
    };

    blend_map := D3D11_BLEND_MAP;
    for descs {
        blend_desc.RenderTarget[it_index] = .{
            BlendEnable           = xx it.blend_enable,
            SrcBlend              = blend_map[it.src_blend],
            DestBlend             = blend_map[it.dest_blend],
            BlendOp               = xx it.blend_op,
            SrcBlendAlpha         = blend_map[it.src_blend_alpha],
            DestBlendAlpha        = blend_map[it.dest_blend_alpha],
            BlendOpAlpha          = xx it.blend_op_alpha,
            RenderTargetWriteMask = xx it.write_mask,
        };
    }

    found, state := table_find(*blend_table, blend_desc);
    if !found {
        ID3D11Device_CreateBlendState(device, *blend_desc, *state);
        table_add(*blend_table, blend_desc, state);
    }

    ID3D11DeviceContext_OMSetBlendState(device_context, state, *blend_factor.component, sample_mask);

}

#assert DXGI_FORMAT_MAP.count == enum_count(Texture_Format);
DXGI_FORMAT_MAP :: DXGI_FORMAT.[
    .UNKNOWN,               // Unknown

    // Fixed point formats
    .R8_UNORM,              // R8
    .R8G8_UNORM,            // RG8
    .R8G8B8A8_UNORM,        // RGBA8
    .R8G8B8A8_UNORM_SRGB,   // RGBA8_SRGB
    .B8G8R8A8_UNORM,        // BGRA8
    .B8G8R8A8_UNORM_SRGB,   // BGRA8_SRGB
    .B5G6R5_UNORM,          // B5G6R5
    .R10G10B10A2_UNORM,     // RGB10A2
    .R16_UNORM,             // R16

    // Floating point formats
    .R16_FLOAT,             // R16F
    .R16G16_FLOAT,          // RG16F
    .R16G16B16A16_FLOAT,    // RGBA16F
    .R32_FLOAT,             // R32F
    .R32G32_FLOAT,          // RG32F
    .R32G32B32A32_FLOAT,    // RGBA32F
    .R11G11B10_FLOAT,       // RG11B10F
    .R9G9B9E5_SHAREDEXP,    // RGB9E5F

    // Integer formats
    .R16_SINT,              // R16I
    .R16G16_SINT,           // RG16I
    .R16G16B16A16_SINT,     // RGBA16I
    .R32_SINT,              // R32I
    .R32G32_SINT,           // RG32I
    .R32G32B32_SINT,        // RGB32I
    .R32G32B32A32_SINT,     // RGBA32I

    // Unsigned integer formats
    .R16_UINT,              // R16U
    .R16G16_UINT,           // RG16U
    .R16G16B16A16_UINT,     // RGBA16U
    .R32_UINT,              // R32U
    .R32G32_UINT,           // RG32U
    .R32G32B32_UINT,        // RGB32U
    .R32G32B32A32_UINT,     // RGBA32U

    // Block compression formats
    .BC6H_UF16,             // BC6U
    .BC6H_SF16,             // BC6S
    .BC7_UNORM,             // BC7
    .BC7_UNORM_SRGB,        // BC7_SRGB

    // Depth formats
    .D16_UNORM,             // D16
    .D24_UNORM_S8_UINT,     // D24S8
    .D32_FLOAT,             // D32F
    .D32_FLOAT_S8X24_UINT   // D32FS8
];

#assert D3D11_BLEND_MAP.count == enum_count(Blend);
D3D11_BLEND_MAP :: D3D11_BLEND.[
    .ZERO,
    .ONE,
    .SRC_COLOR,
    .INV_SRC_COLOR,
    .SRC_ALPHA,
    .INV_SRC_ALPHA,
    .DEST_ALPHA,
    .INV_DEST_ALPHA,
    .DEST_COLOR,
    .INV_DEST_COLOR,
    .SRC_ALPHA_SAT,
    .BLEND_FACTOR,
    .INV_BLEND_FACTOR,
    .SRC1_COLOR,
    .INV_SRC1_COLOR,
    .SRC1_ALPHA,
    .INV_SRC1_ALPHA,
];

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
        log("[Gaco] % %", message.ID, message_str, flags=flags);
    }
    ID3D11InfoQueue_ClearStoredMessages(info);
    safe_release(info);
    return message_str, error;
}

}

d3d11_set_debug_name :: (resource: *ID3D11DeviceChild, name: string) {
    #if DEBUG {
        if !resource return;
        ID3D11DeviceChild_SetPrivateData(
            resource,
            *uid(WKPDID_D3DDebugObjectName),
            cast(u32) name.count,
            name.data
        );
    }
}

ID3DUserDefinedAnnotation_UUID :: "b2daad8b-03d4-4dbf-95eb-32ab4b63d0ab";
ID3DUserDefinedAnnotation :: struct {
    #as using vtable: *ID3DUserDefinedAnnotation_VTable;
}

ID3DUserDefinedAnnotation_VTable :: struct {
    using unknown_vtable: IUnknown_VTable;
    BeginEvent:      #type (self: *ID3DUserDefinedAnnotation, name: *u16) -> s32 #c_call;
    EndEvent:        #type (self: *ID3DUserDefinedAnnotation) -> s32 #c_call;
    SetMarker:       #type (self: *ID3DUserDefinedAnnotation, name: *u16) -> void #c_call;
    GetStatus:       #type (self: *ID3DUserDefinedAnnotation) -> BOOL #c_call;
}

#import "d3d11";
#import "d3d_compiler";
#import "dxgi";
#import "Windows";
#import "Windows_Utf8";
#import "Window_Type";