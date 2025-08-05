// NOTE(Yasin): D3D11 just spins a bunch of threads for lots of different things and
// there doesn't seem to be a way to turn them off. Should investigate more.

Shader :: struct {
    type : Shader_Type;
    vertex_shader: *ID3D11VertexShader;
    input_layout: *ID3D11InputLayout;
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
    sampler_state: *ID3D11SamplerState;
}

Texture :: struct {
    texture: *ID3D11Texture2D;
    union {
        resource_view: *ID3D11ShaderResourceView;
        unordered_access_view: *ID3D11UnorderedAccessView;
    }
    width, height, channels: u32;
    flags: Texture_Flags;
};


is_empty :: (texture: Texture) -> bool {
    return texture.texture == null;
}

is_empty :: (using shader: Shader) -> bool {
    empty_vs := type & .Vertex   && (!vertex_shader || !input_layout);
    empty_fs := type & .Fragment && !fragment_shader;
    empty_cs := type & .Compute  && !compute_shader;

    return type == .Unspecified || empty_vs || empty_fs || empty_cs;
}

init :: (window: HWND, wanted_msaa : u32 = 4) {
    flags : D3D11_CREATE_DEVICE_FLAG;
    #if DEBUG flags |= .DEBUG;
    feature_levels := D3D_FEATURE_LEVEL.[._11_1];

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

    safe_release(dxgi_factory);


    msaa = wanted_msaa;

    // --- States ---

    depth_stencil_desc := D3D11_DEPTH_STENCIL_DESC.{
        DepthEnable = cast(BOOL) true,
        DepthWriteMask = .ALL,
        DepthFunc = .LESS_EQUAL,
        StencilEnable = cast(BOOL) true,

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

    // TODO(Yasin): Add more depth-stencil states.
    depth_stencil_state: *ID3D11DepthStencilState;
    hr = ID3D11Device_CreateDepthStencilState(device, *depth_stencil_desc, *depth_stencil_state);
    check_hr("ID3D11Device.CreateDepthStencilState");

    ID3D11DeviceContext_OMSetDepthStencilState(device_context, depth_stencil_state, 0xFF);
    safe_release(depth_stencil_state);

    rs_desc := D3D11_RASTERIZER_DESC.{
        FillMode = .SOLID,
        CullMode = .BACK,
        DepthClipEnable = 1,
        ScissorEnable = 1,
    };
    ID3D11Device_CreateRasterizerState(device, *rs_desc, *rasterizer_states[Rasterizer_State.Scissor]);

    rs_desc.ScissorEnable = 0;
    ID3D11Device_CreateRasterizerState(device, *rs_desc, *rasterizer_states[Rasterizer_State.Default]);

    rs_desc.CullMode = .FRONT;
    ID3D11Device_CreateRasterizerState(device, *rs_desc, *rasterizer_states[Rasterizer_State.Front_Cull]);

    rs_desc.CullMode = .NONE;
    ID3D11Device_CreateRasterizerState(device, *rs_desc, *rasterizer_states[Rasterizer_State.No_Cull]);

    blend_alpha_desc : D3D11_BLEND_DESC;
    blend_alpha_desc.RenderTarget[0] = .{
        BlendEnable = 1,
        SrcBlend = .SRC_ALPHA,
        DestBlend = .INV_SRC_ALPHA,
        BlendOp = .ADD,
        SrcBlendAlpha = .ONE,
        DestBlendAlpha = .ZERO,
        BlendOpAlpha = .ADD,
        RenderTargetWriteMask = xx D3D11_COLOR_WRITE_ENABLE.ALL,
    };

    ID3D11Device_CreateBlendState(device, *blend_alpha_desc, *blend_states[Blend_State.Alpha]);

    set_primitive_type(.Triangle_List);
}

deinit :: () {
    #if DEBUG
        log_messages_and_get_last();

    for * blend_states {
        safe_release_and_reset(it);
    }
    for * rasterizer_states {
        safe_release_and_reset(it);
    }

    safe_release_and_reset(*depth_stencil_view);
    safe_release_and_reset(*render_target_view);
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
    case .Dynamic;
        bd.Usage = .DYNAMIC;
        bd.CPUAccessFlags = .WRITE;
    case .Immutable;
        bd.Usage = .IMMUTABLE;
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

    init_data : *D3D11_SUBRESOURCE_DATA = null;
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

bind_buffer :: (buffer: Buffer(.Vertex), slot : u32 = 0) {
    offset : u32 = 0;
    ID3D11DeviceContext_IASetVertexBuffers(device_context, slot, 1, *buffer.buffer, *buffer.stride, *offset);
}

bind_buffer :: (buffer: Buffer(.Index)) {
    format : DXGI_FORMAT;
    if      buffer.stride == 2 format = .R16_UINT;
    else if buffer.stride == 4 format = .R32_UINT;
    ID3D11DeviceContext_IASetIndexBuffer(device_context, buffer.buffer, format, 0);
}

bind_buffer :: (buffer: Buffer(.Constant), slot : u32 = 0, bind_to: Shader_Type) {
    if bind_to == .Unspecified {
        log_error("Gaco: Unspecified shader type to bind a constant buffer.");
        return;
    }
    if bind_to & .Vertex
        ID3D11DeviceContext_VSSetConstantBuffers(device_context, slot, 1, *buffer.buffer);
    if bind_to & .Fragment
        ID3D11DeviceContext_PSSetConstantBuffers(device_context, slot, 1, *buffer.buffer);
    if bind_to & .Compute
        ID3D11DeviceContext_CSSetConstantBuffers(device_context, slot, 1, *buffer.buffer);
}

bind_buffer :: (buffer: Buffer(.Structured), slot : u32 = 0, bind_to: Shader_Type) {
    if bind_to == .Unspecified {
        log_error("Gaco: Unspecified shader type to bind a structured buffer.");
        return;
    }
    if bind_to & .Vertex
        ID3D11DeviceContext_VSSetShaderResources(device_context, slot, 1, *buffer.srv);
    if bind_to & .Fragment
        ID3D11DeviceContext_PSSetShaderResources(device_context, slot, 1, *buffer.srv);
    if bind_to & .Compute
        ID3D11DeviceContext_CSSetShaderResources(device_context, slot, 1, *buffer.srv);
}

// TODO(Yasin): OMSetRenderTargetsAndUnorderedAccessViews
bind_buffer :: (buffer: Buffer(.RWStructured), slot : u32 = 0) {
    ID3D11DeviceContext_CSSetUnorderedAccessViews(device_context, slot, 1, *buffer.uav, null);
}

map_buffer :: (buffer: *Buffer, flags: Map_Flags) -> *void {
        subresource : D3D11_MAPPED_SUBRESOURCE;
        d3d11_flags : D3D11_MAP;
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

update_buffer :: (buffer: *Buffer, data: *void) {
    ID3D11DeviceContext_UpdateSubresource(device_context, buffer.buffer, 0, null, data, buffer.stride, 0);
}

// If you create a texture array, this can only update the first one, for now.
update_texture :: (texture: *Texture, data: *void, rect: Rect) {
    rows : u32 = cast(u32)rect.w * texture.channels;

    box: D3D11_BOX;
    box.top = xx rect.y;
    box.left = xx rect.x;
    box.bottom = xx (rect.y + rect.h);
    box.right = xx (rect.x + rect.w);
    box.back = 1;

    ID3D11DeviceContext_UpdateSubresource(device_context, texture.texture, 0, *box, data, rows, 0);
}

update_texture :: inline (texture: *Texture, data: *void) {
    rect: Rect;
    rect.w = texture.width;
    rect.h = texture.height;
    update_texture(texture, data,rect);
}

// Allocates on temp
// NOTE(Yasin): This creates a huge performance penalty.
read_buffer :: (buffer: *Buffer, copy_buffer_to_use: *Buffer(.Copy) = null) -> *void {
    buffer_to_map : *Buffer(.Copy) = ---;

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

// Use write_buffer for buffers with .Dynamic usage and update_buffer for those with .Default usage.
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

write_buffer :: inline (buffer: *Buffer, data: []$T) {
    if size_of(T) != buffer.stride {
        buffer.stride = size_of(T);
    }
    write_buffer(buffer, data.data, data.count * size_of(T));
}

write_buffer :: inline (buffer: *Buffer, data: *$T) {
    // We shouldn't be changing the stride because we might want to just write the
    // first 3 values of a Vector4, for example. (Since D3D11 requires 16 byte aligned constant buffers)

    write_buffer(buffer, data, size_of(T));
}

copy_buffer :: (from: *Buffer, to: *Buffer) {
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
    safe_release_and_reset(*texture.texture);
    safe_release_and_reset(*texture.resource_view);
    if texture.flags & .RWCompute {
        safe_release_and_reset(*texture.unordered_access_view);
    }

    texture.width, texture.height, texture.channels = 0;
    texture.flags = .None;
}

load_shader_from_bytecode :: (bytecode: Shader_Bytecode, type: Shader_Type) -> Shader {
    shader: Shader;
    if type & .Compute {
        hr := ID3D11Device_CreateComputeShader(device, bytecode.cs.data, xx bytecode.cs.count, null, *shader.compute_shader);
        check_hr("ID3D11Device.CreateComputeShader", #code `return .{});

        #if DEBUG {
            ID3D11DeviceChild_SetPrivateData(shader.compute_shader, *uid(WKPDID_D3DDebugObjectName), CS_ENTRY_POINT.count, CS_ENTRY_POINT.data);
        }
    }

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
    shader.type = type;
    return shader;
}


destroy_shader :: (using shader: *Shader) {
    if type & .Vertex
        safe_release_and_reset(*vertex_shader);
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
    compile :: (type: Shader_Type) -> string #expand {
        entry_point, target: string;
        #if type == {
        case .Vertex;
            entry_point = VS_ENTRY_POINT;
            target = "vs_5_0";
        case .Fragment;
            entry_point = FS_ENTRY_POINT;
            target = "ps_5_0";
        case .Compute;
            entry_point = CS_ENTRY_POINT;
            target = "cs_5_0";
        }
        output, errors, hr := D3DCompile(source, shader_name, defines, D3D_COMPILE_STANDARD_FILE_INCLUDE, entry_point, target, xx flags, 0);
        defer free(errors);
        check_hr("D3DCompile", #code {
            // free(bytecode); @Leak
            log_error(errors);
            `return .{}, false;
        });
        return output;
    }

    if type & .Vertex    bytecode.vs = compile(.Vertex);
    if type & .Fragment  bytecode.fs = compile(.Fragment);
    if type & .Compute   bytecode.cs = compile(.Compute);

    return bytecode, true;
}

clear :: (r: float, g: float, b: float, a: float, depth := 1.0, stencil : u8 = 0) {
    color := float.[r, g, b, a];
    ID3D11DeviceContext_ClearRenderTargetView(device_context, render_target_view, *color);
    ID3D11DeviceContext_ClearDepthStencilView(device_context, depth_stencil_view, cast(u32) D3D11_CLEAR_FLAG.DEPTH  | D3D11_CLEAR_FLAG.STENCIL, depth, stencil);
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

set_primitive_type :: (primitive_type : Primitive_Type) {
    topology: D3D11_PRIMITIVE_TOPOLOGY;
    if #complete primitive_type == {
    case .Line_List;
        topology = .TRIANGLELIST;
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
        right = rect.x + rect.w,
        bottom = rect.y + rect.h
    };

    ID3D11DeviceContext_RSSetScissorRects(device_context, 1, *d3d11_rect);
}

set_viewport :: (using rect: Rect) {
    vp : D3D11_VIEWPORT;
    vp.Width = cast(float) w;
    vp.Height = cast(float) h;
    vp.MinDepth = 0.0;
    vp.MaxDepth = 1.0;
    vp.TopLeftX = cast(float) x;
    vp.TopLeftY = cast(float) y;
    ID3D11DeviceContext_RSSetViewports(device_context, 1, *vp);
}

set_blend_state :: (state: Blend_State) {
    ID3D11DeviceContext_OMSetBlendState(device_context, blend_states[state], null, SampleMask=0xFFFFFFFF);
}

set_rasterizer_state :: (state: Rasterizer_State) {
    ID3D11DeviceContext_RSSetState(device_context, rasterizer_states[state]);
}

// base_vertex only makes sense in indexed drawing.
draw :: ($indexed: bool, count: u32, first: u32 = 0, base_vertex : s32 = 0) {
    #if indexed {
        ID3D11DeviceContext_DrawIndexed(device_context, count, first, base_vertex);
    }
    else {
        ID3D11DeviceContext_Draw(device_context, count, first);
    }
}


draw_instanced :: ($indexed: bool, count: u32, instance_count: u32, first: u32 = 0, first_instance: u32 = 0, base_vertex : s32 = 0) {
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
dispatch_compute_indirect :: (buffer: Buffer(.Dispatch_Indirect), byte_offset : u32 = 0) {
    ID3D11DeviceContext_DispatchIndirect(device_context, buffer.buffer, byte_offset);
}

present :: (interval: u32 = 1) {
    hr := IDXGISwapChain_Present(swap_chain, interval, xx DXGI_SWAP_EFFECT.FLIP_DISCARD);
    check_hr("IDXGISwapChain_Present", #code {});
}

resize :: (width: int, height: int) {
    // This doesn't seem to be necessary, but just to be safe...
    if render_target_view {
        ID3D11DeviceContext_OMSetRenderTargets(device_context, 0, null, null);
    }

    safe_release_and_reset(*render_target_view);
    safe_release_and_reset(*depth_stencil_view);

    hr := IDXGISwapChain_ResizeBuffers(swap_chain, 0, cast(u32)width, cast(u32)height, .UNKNOWN, 0);
    check_hr("IDXGISwapChain.ResizeBuffers");

    back_buffer_texture: *ID3D11Texture2D;
    hr = IDXGISwapChain_GetBuffer(swap_chain, 0, *uid(ID3D11Texture2D_UUID), xx *back_buffer_texture);
    check_hr("IDXGISwapChain.GetBuffer");

    hr = ID3D11Device_CreateRenderTargetView(device, back_buffer_texture, null, *render_target_view);
    safe_release(back_buffer_texture);
    check_hr("ID3D11Device.CreateRenderTargetView");


    depth_stencil_texture: *ID3D11Texture2D;
    depth_stencil_texture_desc := D3D11_TEXTURE2D_DESC.{
        Width = cast(u32)width,
        Height = cast(u32)height,
        MipLevels = 1,
        ArraySize = 1,
        Format = .D24_UNORM_S8_UINT,
        SampleDesc.Count = msaa,
        SampleDesc.Quality = 0,
        Usage = .DEFAULT,
        BindFlags = .DEPTH_STENCIL
    };
    hr = ID3D11Device_CreateTexture2D(device, *depth_stencil_texture_desc, null, *depth_stencil_texture);
    check_hr("ID3D11Device.CreateTexture2D");

    hr = ID3D11Device_CreateDepthStencilView(device, depth_stencil_texture, null, *depth_stencil_view);

    safe_release(depth_stencil_texture);
    check_hr("ID3D11Device.CreateDepthStencilView");

    ID3D11DeviceContext_OMSetRenderTargets(device_context, 1, *render_target_view, depth_stencil_view);
    set_viewport(.{0, 0, cast(s32)width, cast(s32)height});
}

// @NotImplemented
set_render_target :: (render_texture: Texture) {
}

create_texture_array :: (data: []*u8, width: u32, height: u32, channels: u32, mip_levels: u32 = 1, flags := Texture_Flags.None) -> Texture {
    cpu_flags: D3D11_CPU_ACCESS_FLAG;

    bind_flags := D3D11_BIND_FLAG.SHADER_RESOURCE;
    misc_flags : D3D11_RESOURCE_MISC_FLAG;
    if flags & .RWCompute
        bind_flags |= .UNORDERED_ACCESS;
    if flags & .Generate_Mips {
        // @Speed: We would probably want to create a seperate render target texture
        // and copy it to our newly generated texture.
        bind_flags |= .RENDER_TARGET;
        misc_flags |= .GENERATE_MIPS;
    }

    if flags & .Cubemap
        misc_flags |= .TEXTURECUBE;

    formats : [4]DXGI_FORMAT = ---;

    if flags & .SRGB {
        formats = DXGI_FORMAT.[.UNKNOWN, .UNKNOWN, .UNKNOWN, .R8G8B8A8_UNORM_SRGB];
    }
    else {
        formats = DXGI_FORMAT.[.R8_UNORM, .R8G8_UNORM, .UNKNOWN, .R8G8B8A8_UNORM];
    }

    texture_format := formats[channels-1];
    if texture_format == .UNKNOWN {
        recommended_channels := ifx flags & .SRGB "4" else "4, 2 or 1";
        log_error("Gaco: Error while creating texture - % channels is not compatible with  Please create your image with % channels.", channels, recommended_channels);
        return .{};
    }

    texture_desc := D3D11_TEXTURE2D_DESC.{
        Width = width,
        Height = height,
        SampleDesc.Count = 1,
        MipLevels = mip_levels,
        ArraySize = ifx data cast(u32)data.count else 1,
        Format = texture_format,
        Usage = .DEFAULT,
        BindFlags = bind_flags,
        CPUAccessFlags = cpu_flags,
        MiscFlags = misc_flags
    };

    texture := Texture.{width = width, height = height, channels = channels, flags = flags};

    init_data : []D3D11_SUBRESOURCE_DATA;
    if !(flags & .Generate_Mips) && data {
        init_data = NewArray(data.count, D3D11_SUBRESOURCE_DATA,, temp);
        for * init_data {
            it.* = D3D11_SUBRESOURCE_DATA.{
                pSysMem = data[it_index],
                SysMemPitch = width * channels,
                SysMemSlicePitch = 0,
            };
        }
    }

    hr := ID3D11Device_CreateTexture2D(device, *texture_desc, init_data.data, *texture.texture );
    check_hr("ID3D11Device.CreateTexture2D", #code return .{});

    // :Multithreading:
    // https://learn.microsoft.com/en-us/windows/win32/direct3d11/overviews-direct3d-11-render-multi-thread-intro
    if flags & .Generate_Mips {
        for data {
            index := cast(u32)it_index * mip_levels;
            ID3D11DeviceContext_UpdateSubresource(device_context, texture.texture, index, null, it, width * channels, 1);
        }
    }

    if flags & .RWCompute {
        uav_desc := D3D11_UNORDERED_ACCESS_VIEW_DESC.{
            Format = texture_format,
            ViewDimension = .TEXTURE2D,
            Texture2D.MipSlice = 0
        };
        hr = ID3D11Device_CreateUnorderedAccessView(device, texture.texture, *uav_desc, *texture.unordered_access_view);
        check_hr("ID3D11Device.CreateUnorderedAccessView", #code return .{});
    }
    else {
        srv_desc := D3D11_SHADER_RESOURCE_VIEW_DESC.{
            Format = texture_format,
            ViewDimension = ifx flags & .Cubemap then .TEXTURECUBE else .TEXTURE2D,
            Texture2D.MostDetailedMip = 0,
            Texture2D.MipLevels = mip_levels
        };

        hr = ID3D11Device_CreateShaderResourceView(device, texture.texture, *srv_desc, *texture.resource_view);
        check_hr("ID3D11Device.CreateShaderResourceView", #code return .{});

        // :Multithreading:
        if flags & .Generate_Mips {
            ID3D11DeviceContext_GenerateMips(device_context, texture.resource_view);
        }
    }
    return texture;

}

// Actually, mip_levels without .Generate_Mips doesn't make any sense in here
create_texture :: inline (data: *u8, width: u32, height: u32, channels: u32, mip_levels: u32 = 1, flags := Texture_Flags.None) -> Texture {
    data_array: []*u8;
    if data {
        if flags & .Cubemap {
            data_array = .[data,data,data,data,data,data];
        }
        else {
            data_array = .[data];
        }
    }

    return create_texture_array(data_array, width, height, channels, mip_levels, flags);
}

bind_texture :: (texture: Texture, slot: u32) {
    if texture.flags & .RWCompute {
        ID3D11DeviceContext_CSSetUnorderedAccessViews(device_context, slot, 1, *texture.unordered_access_view, null);
    }
    else {
        ID3D11DeviceContext_PSSetShaderResources(device_context, slot, 1, *texture.resource_view);
    }
}

copy_texture :: (from: *Texture, to: *Texture) {
    ID3D11DeviceContext_CopyResource(device_context, to.texture, from.texture);
}

// @Incomplete: give more options
create_sampler :: (filtering := Sampler_Filtering.Linear, edge_handling := Sampler_Edge_Handling.Wrap, max_anisotropy : u32 = 1) -> Sampler {
    d3d11_filter: D3D11_FILTER;
    if #complete filtering == {
    case .Linear;  d3d11_filter = .MIN_MAG_MIP_LINEAR;
    case .Nearest; d3d11_filter = .MIN_MAG_MIP_POINT;
    }

    address_mode: D3D11_TEXTURE_ADDRESS_MODE;
    if #complete edge_handling == {
    case .Wrap;   address_mode = .WRAP;
    case .Mirror; address_mode = .MIRROR;
    case .Clamp;  address_mode = .CLAMP;
    case .Border; address_mode = .BORDER;
    }

    // @Incomplete
    // Max anisotropy requires a specific filter (.ANISOTROPY) on D3D11, while there isn't such a requirement on OpenGL.
    // So I am not sure on how to handle this.
    // We just pass it to the sampler without changing the filtering for now, which does nothing.
    sampler_desc := D3D11_SAMPLER_DESC.{
        Filter = d3d11_filter,
        AddressU = address_mode, AddressV = address_mode, AddressW = address_mode,
        MaxAnisotropy = max_anisotropy,
        ComparisonFunc = .ALWAYS,
        MinLOD = 0,
        MaxLOD = cast(float32)D3D11_FLOAT32_MAX,
    };

    sampler: Sampler;
    hr := ID3D11Device_CreateSamplerState(device, *sampler_desc,*sampler.sampler_state);
    check_hr("ID3D11Device.CreateSamplerState", #code `return .{});
    return sampler;
}

bind_sampler :: (sampler: Sampler, slot: u32) {
    ID3D11DeviceContext_PSSetSamplers(device_context, slot, 1, *sampler.sampler_state);
}

destroy_sampler :: (sampler: *Sampler) {
    safe_release_and_reset(*sampler.sampler_state);
}

#scope_module
VS_EXTENSION :: ".dxvs";
FS_EXTENSION :: ".dxfs";
CS_EXTENSION :: ".dxcs";

#scope_file
// This spins up like... 20 threads
// Threads remain alive indefinitely even after we destroy the reflection object.
// Sad.
get_input_layout_from_bytecode :: (bytecode: string) -> *ID3D11InputLayout {
    reflector: *ID3D11ShaderReflection;
    defer safe_release(reflector);

    hr := D3DReflect(bytecode.data, xx bytecode.count, *uid(ID3D11ShaderReflection_UUID), cast(**void)*reflector);
    check_hr("D3DReflect", #code `return null);

    shader_desc: D3D11_SHADER_DESC;
    ID3D11ShaderReflection_GetDesc(reflector, *shader_desc);

    input_layout: *ID3D11InputLayout;
    input_layout_desc: [..]D3D11_INPUT_ELEMENT_DESC;

    for 0..shader_desc.InputParameters-1 {
        using param_desc: D3D11_SIGNATURE_PARAMETER_DESC;
        hr := ID3D11ShaderReflection_GetInputParameterDesc(reflector, it, *param_desc);
        check_hr("ID3D11ShaderReflection.GetInputParameterDesc", #code `return null);

        element_desc: D3D11_INPUT_ELEMENT_DESC;
        element_desc.SemanticName = SemanticName;
        element_desc.SemanticIndex = SemanticIndex;
        element_desc.AlignedByteOffset = D3D11_APPEND_ALIGNED_ELEMENT;

        // InputSlot is @Hardcoded right now. There may be reasons to want to change this
        // but there is no way to get it from the shader code and I don't want to force people
        // to pass an input layout.

        // Instance data is passed to the slot 1 (in bind_buffer) and vertex data to the slot 0.
        if starts_with(to_string(SemanticName), "INST_") {
            element_desc.InputSlot = 1;
            element_desc.InputSlotClass = .INSTANCE_DATA;
            element_desc.InstanceDataStepRate = 1; // How often is something other than 1 is used in instancing?
        }
        else {
            element_desc.InputSlot = 0;
            element_desc.InputSlotClass = .VERTEX_DATA;
            element_desc.InstanceDataStepRate = 0;
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
        fail_message: string;
        // https://learn.microsoft.com/tr-tr/windows/win32/direct3d11/d3d11-graphics-reference-returnvalues
        if `hr == {
        case 0x887C0002;                   fail_message = "The file was not found.";
        case 0x887C0001;                   fail_message = "There are too many unique instances of a particular type of state object.";
        case 0x887C0003;                   fail_message = "There are too many unique instances of a particular type of view object.";
        case 0x887C0004;                   fail_message = "The first call to ID3D11DeviceContext::Map was not D3D11_MAP_WRITE_DISCARD.";

        case DXGI_ERROR_INVALID_CALL;      fail_message = "The procedure call is invalid.";
        case DXGI_ERROR_WAS_STILL_DRAWING; fail_message = "The previous blit operation that is transferring information to or from this surface is incomplete.";
        case;
            System :: #import "System";
            _, fail_message = System.get_error_value_and_string();
        }

        log_error("% failed with code 0x%: %\n", from, FormatInt.{value = `hr, base=16}, fail_message);
        #if !DEBUG {
            log("Pass DEBUG=true when importing Gaco to learn more.");
        }

        #insert code_to_insert_after_fail;
    }
}

using D3D11_State : struct {
    device: *ID3D11Device;
    device_context: *ID3D11DeviceContext;
    swap_chain: *IDXGISwapChain1;
    render_target_view: *ID3D11RenderTargetView;
    depth_stencil_view: *ID3D11DepthStencilView;

    // Should we expose a way to create these states?
    rasterizer_states: [#run enum_highest_value(Rasterizer_State) + 1]*ID3D11RasterizerState;
    blend_states: [#run enum_highest_value(Blend_State) + 1]*ID3D11BlendState;

    msaa : u32;
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
        logged_ids : [..]D3D11_MESSAGE_ID;
        message_str: string;
        sb: String_Builder;
        error := false;
        for i: 0..message_count-1 {
            message_size : u64;
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
            log("Gaco: % - %\n", message.ID, message_str, flags=flags);
        }
        ID3D11InfoQueue_ClearStoredMessages(info);
        safe_release(info);
        return message_str, error;
    }
}