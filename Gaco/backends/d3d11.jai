Shader :: struct {
    type : Shader_Type;
    union {
        struct {
            vertex_shader: *ID3D11VertexShader;
            pixel_shader: *ID3D11PixelShader;
            input_layout: *ID3D11InputLayout;
        }
        compute_shader: *ID3D11ComputeShader;
    }
}

Buffer :: struct (type: Buffer_Type) {
    buffer: *ID3D11Buffer;
    count: u32;
    stride: u32;
    #if type == {
    case .Structured;   srv: *ID3D11ShaderResourceView;
    case .RWStructured; uav: *ID3D11UnorderedAccessView;
    }
};

Sampler :: struct {
    sampler_state: *ID3D11SamplerState;
}

Texture :: struct {
    texture: *ID3D11Texture2D;
    resource_view: *ID3D11ShaderResourceView;
    width, height, channels: u32;
};

init :: (window: HWND, wanted_msaa : u32 = 4) {
    flags : D3D11_CREATE_DEVICE_FLAG;
    #if DEBUG flags |= .DEBUG;
    feature_levels := D3D_FEATURE_LEVEL.[._11_1];

    hr := D3D11CreateDevice(null, .HARDWARE, null, xx flags, feature_levels.data, feature_levels.count, D3D11_SDK_VERSION, *D3D11.device, null, *D3D11.device_context);
    check_hr("D3D11CreateDevice");

    #if DEBUG {
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
        hr = IUnknown_QueryInterface(D3D11.device, *uid(IDXGIDevice2_UUID), xx *dxgi_device);
        check_hr("IUnknown.QueryInterface");
        dxgi_adapter: *IDXGIAdapter;
        hr = IDXGIDevice_GetAdapter(dxgi_device, *dxgi_adapter);
        check_hr("IDXGIDevice.GetAdapter");

        hr = IDXGIObject_GetParent(dxgi_adapter, *uid(IDXGIFactory2_UUID), xx *dxgi_factory);
        check_hr("IDXGIObject.GetParent");

        IUnknown_Release(dxgi_adapter);
        IUnknown_Release(dxgi_device);
    }
    hr = IDXGIFactory2_CreateSwapChainForHwnd(dxgi_factory, D3D11.device, window, *swap_chain_desc, null, null, *D3D11.swap_chain);
    check_hr("IDXGIFactory2.CreateSwapChainForHwnd");
    IUnknown_Release(dxgi_factory);


    D3D11.msaa = wanted_msaa;

    // --- States ---

    // @Unused: stencil buffer
    depth_stencil_desc := D3D11_DEPTH_STENCIL_DESC.{
        DepthEnable = cast(BOOL) true,
        DepthWriteMask = .ALL,
        DepthFunc = .LESS_EQUAL,
    };

    depth_stencil_state: *ID3D11DepthStencilState;
    hr = ID3D11Device_CreateDepthStencilState(D3D11.device, *depth_stencil_desc, *depth_stencil_state);
    check_hr("ID3D11Device.CreateDepthStencilState");

    ID3D11DeviceContext_OMSetDepthStencilState(D3D11.device_context, depth_stencil_state, 0xFF);
    IUnknown_Release(depth_stencil_state);

    // Everything default except for scissor.
    rasterizer_desc := D3D11_RASTERIZER_DESC.{
        FillMode = .SOLID,
        CullMode = .BACK,
        DepthClipEnable = 1,
        ScissorEnable = 1,
    };
    ID3D11Device_CreateRasterizerState(D3D11.device, *rasterizer_desc, *D3D11.scissor_state);

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

    ID3D11Device_CreateBlendState(D3D11.device, *blend_alpha_desc, *D3D11.blend_alpha_state);

    set_primitive_type(.Triangle_List);
}

deinit :: () {
    IUnknown_Release(D3D11.device);
    IUnknown_Release(D3D11.device_context);
    IUnknown_Release(D3D11.swap_chain);
    IUnknown_Release(D3D11.render_target_view);
    IUnknown_Release(D3D11.depth_stencil_view);
    IUnknown_Release(D3D11.scissor_state);
    IUnknown_Release(D3D11.blend_alpha_state);

    log_messages_and_get_last();
}

create_buffer :: (data: *void, count: u32, stride: u32, $type: Buffer_Type, usage := Buffer_Usage.Default) -> Buffer(type) {
    buffer: Buffer(type);
    buffer.count = count;
    buffer.stride = stride;

    bd := D3D11_BUFFER_DESC.{
        ByteWidth = buffer.count * buffer.stride
    };

    if usage == .Dynamic {
        bd.Usage = .DYNAMIC;
        bd.CPUAccessFlags = .WRITE;
    }
    else if usage == .Immutable {
        bd.Usage = .IMMUTABLE;
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
        bd.StructureByteStride = buffer.stride;
    case .RWStructured;
        bd.BindFlags = .UNORDERED_ACCESS;
        bd.MiscFlags = .BUFFER_STRUCTURED;
        bd.StructureByteStride = buffer.stride;
    case .Copy;
        bd.Usage = .STAGING;
        bd.CPUAccessFlags |= .READ;
    }
    init_data : *D3D11_SUBRESOURCE_DATA = null;

    if data != null {
        init_data = * (D3D11_SUBRESOURCE_DATA.{
            pSysMem = data
        });
    }

    hr := ID3D11Device_CreateBuffer(D3D11.device, *bd, init_data, *buffer.buffer);
    check_hr("ID3D11Device.CreateBuffer", #code `return .{});

    #if type == .Structured {
        srv_desc := D3D11_SHADER_RESOURCE_VIEW_DESC.{
            ViewDimension = .BUFFER,
            Buffer.NumElements = count
        };
        hr = ID3D11Device_CreateShaderResourceView(D3D11.device, buffer.buffer, *srv_desc, *buffer.srv);
        check_hr("ID3D11Device.CreateShaderResourceView", #code `return .{});
    }

    else #if type == .RWStructured {
        uav_desc := D3D11_UNORDERED_ACCESS_VIEW_DESC.{
            ViewDimension = .BUFFER,
            Buffer.NumElements = count
        };
        hr = ID3D11Device_CreateUnorderedAccessView(D3D11.device, buffer.buffer, *uav_desc, *buffer.uav);
        check_hr("ID3D11Device.CreateUnorderedAccessView", #code `return .{});
    }

    return buffer;
}

bind_buffer :: (buffer: Buffer(.Vertex), slot : u32 = 0) {
    offset : u32 = 0;
    ID3D11DeviceContext_IASetVertexBuffers(D3D11.device_context, slot, 1, *buffer.buffer, *buffer.stride, *offset);
    FrameInfo.num_bound_vertices = buffer.count;
}

bind_buffer :: (buffer: Buffer(.Index)) {
    format : DXGI_FORMAT;
    if      buffer.stride == 2 format = .R16_UINT;
    else if buffer.stride == 4 format = .R32_UINT;
    ID3D11DeviceContext_IASetIndexBuffer(D3D11.device_context, buffer.buffer, format, 0);
    FrameInfo.num_bound_indices = buffer.count;
}

bind_buffer :: (buffer: Buffer(.Constant), bind_to: Shader_Type, slot : u32 = 0) {
    if bind_to == .Unspecified {
        log_error("Gaco: Unspecified shader type to bind a constant buffer.");
        return;
    }
    if bind_to & .Vertex
        ID3D11DeviceContext_VSSetConstantBuffers(D3D11.device_context, slot, 1, *buffer.buffer);
    if bind_to & .Fragment
        ID3D11DeviceContext_PSSetConstantBuffers(D3D11.device_context, slot, 1, *buffer.buffer);
    if bind_to & .Compute
        ID3D11DeviceContext_CSSetConstantBuffers(D3D11.device_context, slot, 1, *buffer.buffer);
}

bind_buffer :: (buffer: Buffer(.Structured), bind_to: Shader_Type, slot : u32 = 0) {
    if bind_to == .Unspecified {
        log_error("Gaco: Unspecified shader type to bind a structured buffer.");
        return;
    }
    if bind_to & .Vertex
        ID3D11DeviceContext_VSSetShaderResources(D3D11.device_context, slot, 1, *buffer.srv);
    if bind_to & .Fragment
        ID3D11DeviceContext_PSSetShaderResources(D3D11.device_context, slot, 1, *buffer.srv);
    if bind_to & .Compute
        ID3D11DeviceContext_CSSetShaderResources(D3D11.device_context, slot, 1, *buffer.srv);
}

// TODO(Yasin): OMSetRenderTargetsAndUnorderedAccessViews
bind_buffer :: (buffer: Buffer(.RWStructured), slot : u32 = 0) {
    ID3D11DeviceContext_CSSetUnorderedAccessViews(D3D11.device_context, slot, 1, *buffer.uav, null);
}

map_buffer :: (buffer: *Buffer, flags: Map_Flags) -> *void {
        subresource : D3D11_MAPPED_SUBRESOURCE;
        d3d11_flags : D3D11_MAP;
        if flags & .Read  d3d11_flags |= .READ;
        if flags & .Write d3d11_flags |= .WRITE_DISCARD;

        hr := ID3D11DeviceContext_Map(D3D11.device_context, buffer.buffer, 0, d3d11_flags, 0, *subresource);
        check_hr("ID3D11DeviceContext.Map", #code return null);
        return subresource.pData;
}

unmap_buffer :: (buffer: *Buffer) {
    ID3D11DeviceContext_Unmap(D3D11.device_context, buffer.buffer, 0);
}

update_buffer :: (buffer: *Buffer, data: *void) {
    ID3D11DeviceContext_UpdateSubresource(D3D11.device_context, buffer.buffer, 0, null, data, buffer.stride, buffer.count);
}

update_texture :: (texture: *Texture, data: *void, rect : Rect) {
    rows : u32 = rect.w * texture.channels;

    box: D3D11_BOX;
    box.top = rect.y;
    box.left = rect.x;
    box.bottom = (rect.y + rect.h);
    box.right = (rect.x + rect.w);
    box.back = 1;

    ID3D11DeviceContext_UpdateSubresource(D3D11.device_context, texture.texture, 0, *box, data, rows, rows * rect.h);
}

update_texture :: (texture: *Texture, data: *void) {
    rect: Rect;
    rect.w = texture.width;
    rect.h = texture.height;
    update_texture(texture, data,rect);
}

// Allocates on temp
read_buffer :: (buffer: *Buffer, copy_buffer_to_use: *Buffer(.Copy) = null) -> *void {
    buffer_to_map : *Buffer(.Copy) = ---;

    if copy_buffer_to_use {
        buffer_to_map = copy_buffer_to_use;
    }
    else {
        buffer_to_map = * (create_buffer(null, buffer.count, buffer.stride, .Copy));
    }

    copy_buffer(buffer, buffer_to_map);

    size := cast(int)buffer.count * cast(int)buffer.stride;
    data := alloc(size,, temp);

    mapped_data := map_buffer(buffer_to_map, .Read);
    memcpy(data, mapped_data, size);
    unmap_buffer(buffer_to_map);
    if !copy_buffer_to_use destroy_buffer(buffer_to_map);
    return data;
}

write_buffer :: (buffer: *$T/Buffer, data: *void) #modify {
    return T == Buffer(.Structured) || T == Buffer(.RWStructured);
} {
    copy_buffer_to_map := * (create_buffer(null, buffer.count, buffer.stride, .Copy, .Dynamic));
    write_buffer(copy_buffer_to_map, data);
    copy_buffer(copy_buffer_to_map, buffer);
    destroy_buffer(copy_buffer_to_map);
}

write_buffer :: (buffer: *Buffer, data: *void) {
    size := cast(int)buffer.count * cast(int)buffer.stride;
    mapped_data := map_buffer(buffer, .Write);
    memcpy(mapped_data, data, size);
    unmap_buffer(buffer);
}

copy_buffer :: (from: *Buffer, to: *Buffer) {
    ID3D11DeviceContext_CopyResource(D3D11.device_context, to.buffer, from.buffer);
}

destroy_buffer :: (buffer: *Buffer) {
    IUnknown_Release(buffer.buffer);
    buffer.buffer = null;

    #if buffer.type == .Structured   {
        IUnknown_Release(buffer.srv);
        buffer.srv = null;
    }
    else #if buffer.type == .RWStructured {
        IUnknown_Release(buffer.uav);
        buffer.uav = null;
    }

    buffer.count, buffer.stride = 0;
}

destroy_texture :: (texture: *Texture) {
    IUnknown_Release(texture.texture);
    IUnknown_Release(texture.resource_view);
    texture.texture, texture.resource_view = null;
    texture.width, texture.height = 0;
}

load_shader :: (file_name: string, type: Shader_Type) -> Shader {
    shader: Shader;

    bytecode := load_shader_bytecode(file_name, type);
    if type & .Compute {
        assert(type == .Compute, "Compute shader cannot be used with other shader types.");
        hr := ID3D11Device_CreateComputeShader(D3D11.device, bytecode.cs.data, xx bytecode.cs.count, null, *shader.compute_shader);
        check_hr("ID3D11Device.CreateComputeShader", #code `return .{});
        free(bytecode.cs);

        #if DEBUG {
            ID3D11DeviceChild_SetPrivateData(shader.compute_shader, *uid(WKPDID_D3DDebugObjectName), CS_ENTRY_POINT.count, CS_ENTRY_POINT.data);
        }
    }

    if type & .Vertex {
        hr := ID3D11Device_CreateVertexShader(D3D11.device, bytecode.vs.data, xx bytecode.vs.count, null, *shader.vertex_shader);
        check_hr("ID3D11Device.CreateVertexShader", #code `return .{});

        shader.input_layout = get_input_layout_from_bytecode(bytecode.vs);
        free(bytecode.vs);

        #if DEBUG {
            ID3D11DeviceChild_SetPrivateData(shader.vertex_shader, *uid(WKPDID_D3DDebugObjectName), VS_ENTRY_POINT.count, VS_ENTRY_POINT.data);
        }
    }

    if type & .Fragment {
        hr := ID3D11Device_CreatePixelShader(D3D11.device, bytecode.fs.data, xx bytecode.fs.count, null, *shader.pixel_shader);
        check_hr("ID3D11Device.CreatePixelShader", #code `return .{});
        free(bytecode.fs);

        #if DEBUG {
            ID3D11DeviceChild_SetPrivateData(shader.pixel_shader,*uid(WKPDID_D3DDebugObjectName), FS_ENTRY_POINT.count, FS_ENTRY_POINT.data);
        }
    }

    shader.type = type;
    return shader;
}

compile_shader_to_bytecode :: (source: string, type: Shader_Type, shader_file_name: string) -> Shader_Bytecode, bool {
    bytecode: Shader_Bytecode;
    flags := D3DCOMPILE.ENABLE_STRICTNESS;
    defines: []D3D_SHADER_MACRO;
    #if DEBUG {
        flags |= .DEBUG;
        flags |= .SKIP_OPTIMIZATION;
    }
    compile :: (type: Shader_Type) -> string #expand {
        entry_point, target: string;
        if type == {
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
        output, errors, hr := D3DCompile(source, shader_file_name, defines, D3D_COMPILE_STANDARD_FILE_INCLUDE, entry_point, target, xx flags, 0);
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

set_shader :: (shader: Shader) {
    if shader.type & .Vertex {
        ID3D11DeviceContext_IASetInputLayout(D3D11.device_context, shader.input_layout);
        ID3D11DeviceContext_VSSetShader(D3D11.device_context, shader.vertex_shader, null, 0);
    }
    if shader.type & .Fragment {
        ID3D11DeviceContext_PSSetShader(D3D11.device_context, shader.pixel_shader, null, 0);
    }
    if shader.type & .Compute {
        ID3D11DeviceContext_CSSetShader(D3D11.device_context, shader.compute_shader, null, 0);
    }
}

clear :: (r: float, g: float, b: float, a: float, depth := 1.0) {
    color := float.[r, g, b, a];
    ID3D11DeviceContext_ClearRenderTargetView(D3D11.device_context, D3D11.render_target_view, *color);
    ID3D11DeviceContext_ClearDepthStencilView(D3D11.device_context, D3D11.depth_stencil_view, cast(u32) D3D11_CLEAR_FLAG.DEPTH  | D3D11_CLEAR_FLAG.STENCIL, depth, 0);
}

set_primitive_type :: (primitive_type : Primitive_Type) {
    topology: D3D11_PRIMITIVE_TOPOLOGY;
    if #complete primitive_type == {
    case .Triangle_List;
        topology = .TRIANGLELIST;
    case .Triangle_Strip;
        topology = .TRIANGLESTRIP;
    }
    ID3D11DeviceContext_IASetPrimitiveTopology(D3D11.device_context, topology);
}

enable_scissor :: () {
    ID3D11DeviceContext_RSSetState(D3D11.device_context, D3D11.scissor_state);
}

disable_scissor :: () {
    ID3D11DeviceContext_RSSetState(D3D11.device_context, null); // Sets to default
}

set_scissor :: (rect: Rect) {
    d3d11_rect := D3D11_RECT.{
        left = rect.x,
        top = rect.y,
        right = rect.x + rect.w,
        bottom = rect.y + rect.h
    };

    ID3D11DeviceContext_RSSetScissorRects(D3D11.device_context, 1, *d3d11_rect);
}

set_blend :: (state: Blend_State) {
    states := (*ID3D11BlendState).[null, D3D11.blend_alpha_state];
    ID3D11DeviceContext_OMSetBlendState(D3D11.device_context, states[state], null, SampleMask=0xFFFFFFFF);
}

draw :: (indexed := false, count: u32 = 0, first: u32 = 0) {
    if indexed {
        ID3D11DeviceContext_DrawIndexed(D3D11.device_context, ifx count == 0 FrameInfo.num_bound_indices else count, first, 0);
    }
    else {
        ID3D11DeviceContext_Draw(D3D11.device_context, ifx count == 0 FrameInfo.num_bound_vertices else count, first);
    }
}


draw_instanced :: (indexed := false, instance_count: u32, count: u32 = 0, first: u32 = 0, first_instance: u32 = 0) {
    if indexed {
        ID3D11DeviceContext_DrawIndexedInstanced(D3D11.device_context, ifx count == 0 FrameInfo.num_bound_indices else count, instance_count, first, 0, first_instance);
    }
    else {
        ID3D11DeviceContext_DrawInstanced(D3D11.device_context, ifx count == 0 FrameInfo.num_bound_vertices else count, instance_count, first, first_instance);
    }
}

present :: (interval: u32 = 1) {
    hr := IDXGISwapChain_Present(D3D11.swap_chain, interval, xx DXGI_SWAP_EFFECT.FLIP_DISCARD);
    check_hr("IDXGISwapChain_Present", #code {});
}

resize :: (width: int, height: int) {
    if D3D11.render_target_view {
        ID3D11DeviceContext_OMSetRenderTargets(D3D11.device_context, 0, null, null);
        IUnknown_Release(D3D11.render_target_view);
        D3D11.render_target_view = null;
    }

    if D3D11.depth_stencil_view {
        IUnknown_Release(D3D11.depth_stencil_view);
        D3D11.depth_stencil_view = null;
    }

    hr := IDXGISwapChain_ResizeBuffers(D3D11.swap_chain, 0, cast(u32)width, cast(u32)height, .UNKNOWN, 0);
    check_hr("IDXGISwapChain.ResizeBuffers");

    back_buffer_texture: *ID3D11Texture2D;
    hr = IDXGISwapChain_GetBuffer(D3D11.swap_chain, 0, *uid(ID3D11Texture2D_UUID), xx *back_buffer_texture);
    check_hr("IDXGISwapChain.GetBuffer");

    hr = ID3D11Device_CreateRenderTargetView(D3D11.device, back_buffer_texture, null, *D3D11.render_target_view);
    IUnknown_Release(back_buffer_texture);
    check_hr("ID3D11Device.CreateRenderTargetView");


    depth_stencil_texture: *ID3D11Texture2D;
    depth_stencil_texture_desc := D3D11_TEXTURE2D_DESC.{
        Width = cast(u32)width,
        Height = cast(u32)height,
        MipLevels = 1,
        ArraySize = 1,
        Format = .D24_UNORM_S8_UINT,
        SampleDesc.Count = D3D11.msaa,
        SampleDesc.Quality = 0,
        Usage = .DEFAULT,
        BindFlags = .DEPTH_STENCIL
    };
    hr = ID3D11Device_CreateTexture2D(D3D11.device, *depth_stencil_texture_desc, null, *depth_stencil_texture);
    check_hr("ID3D11Device.CreateTexture2D");

    hr = ID3D11Device_CreateDepthStencilView(D3D11.device, depth_stencil_texture, null, *D3D11.depth_stencil_view);
    IUnknown_Release(depth_stencil_texture);
    check_hr("ID3D11Device.CreateDepthStencilView");

    ID3D11DeviceContext_OMSetRenderTargets(D3D11.device_context, 1, *D3D11.render_target_view, D3D11.depth_stencil_view);

    vp : D3D11_VIEWPORT;
    vp.Width = xx width;
    vp.Height = xx height;
    vp.MinDepth = 0.0;
    vp.MaxDepth = 1.0;
    vp.TopLeftX = 0;
    vp.TopLeftY = 0;
    ID3D11DeviceContext_RSSetViewports(D3D11.device_context, 1, *vp);
}

dispatch_compute :: (num_groups_x: u32, num_groups_y: u32, num_groups_z: u32) {
    ID3D11DeviceContext_Dispatch(D3D11.device_context, num_groups_x, num_groups_y, num_groups_z);
}

create_texture :: (data: *u8, width: u32, height: u32, channels: u32, read := false, write := false) -> Texture {
    cpu_flags: D3D11_CPU_ACCESS_FLAG;
    if read  cpu_flags |= .READ;
    if write cpu_flags |= .WRITE;

    // @Incomplete: Support other formats (HDR etc.)
    formats := DXGI_FORMAT.[.R8_UNORM, .R8G8_UNORM, .UNKNOWN, .R8G8B8A8_UNORM];
    texture_format := formats[channels-1];

    texture_desc := D3D11_TEXTURE2D_DESC.{
        Width = width,
        Height = height,
        SampleDesc.Count = 1,
        MipLevels = 1,
        ArraySize = 1,
        Format = texture_format,
        Usage = .DEFAULT,
        BindFlags = .SHADER_RESOURCE,
        CPUAccessFlags = cpu_flags,
    };


    init_data : *D3D11_SUBRESOURCE_DATA = null;
    if data {
        init_data = * (D3D11_SUBRESOURCE_DATA.{
            pSysMem = data,
            SysMemPitch = width * channels,
            SysMemSlicePitch = 0,
        });
    }

    texture := Texture.{width = width, height = height, channels = channels};

    hr := ID3D11Device_CreateTexture2D(D3D11.device, *texture_desc, init_data, *texture.texture );
    check_hr("ID3D11Device.CreateTexture2D", #code return .{});
    hr = ID3D11Device_CreateShaderResourceView(D3D11.device, texture.texture, null, *texture.resource_view);
    check_hr("ID3D11Device.CreateShaderResourceView", #code return .{});

    return texture;
}

bind_texture :: (texture: Texture, slot: u32) {
    ID3D11DeviceContext_PSSetShaderResources(D3D11.device_context, slot, 1, *texture.resource_view);
}

// @Incomplete: give more options
create_sampler :: (filtering := Sampler_Filtering.Linear, edge_handling := Sampler_Edge_Handling.Wrap) -> Sampler {
    d3d11_filter: D3D11_FILTER;
    if filtering == {
    case .Linear;  d3d11_filter = .MIN_MAG_MIP_LINEAR;
    case .Nearest; d3d11_filter = .MIN_MAG_MIP_POINT;
    }

    // Since all the enum values are equal to their D3D11 counterparts.
    address_mode := cast(D3D11_TEXTURE_ADDRESS_MODE)edge_handling;

    sampler_desc := D3D11_SAMPLER_DESC.{
        Filter = d3d11_filter,
        AddressU = address_mode, AddressV = address_mode, AddressW = address_mode,
        MaxAnisotropy = 1,
        ComparisonFunc = .ALWAYS,
        MaxLOD = cast(float32)D3D11_FLOAT32_MAX,
    };

    sampler: Sampler;
    hr := ID3D11Device_CreateSamplerState(D3D11.device, *sampler_desc,*sampler.sampler_state);
    check_hr("ID3D11Device.CreateSamplerState", #code `return .{});
    return sampler;
}

bind_sampler :: (sampler: Sampler, slot: u32) {
    ID3D11DeviceContext_PSSetSamplers(D3D11.device_context, slot, 1, *sampler.sampler_state);
}

#scope_module
VS_EXTENSION :: ".dxvs";
FS_EXTENSION :: ".dxfs";
CS_EXTENSION :: ".dxcs";

#scope_file
get_input_layout_from_bytecode :: (bytecode: string) -> *ID3D11InputLayout {
    // @Cleanup
    // @Hardcoded: has to be this way until jai includes IID_ID3D11ShaderReflection in its d3d_compiler module
    IID_ID3D11ShaderReflection :: IID.{Data1=0x8D536CA1, Data2=0x0CCA, Data3=0x4956,
    Data4=.[0xA8, 0x37, 0x78, 0x69, 0x63, 0x75, 0x55, 0x84]};

    reflector: *ID3D11ShaderReflection;
    hr := D3DReflect(bytecode.data, xx bytecode.count, IID_ID3D11ShaderReflection, cast(**void) *reflector);
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

    hr = ID3D11Device_CreateInputLayout(D3D11.device, input_layout_desc.data, cast(u32) input_layout_desc.count, bytecode.data, cast(u64) bytecode.count, *input_layout);
    check_hr("ID3D11Device.CreateInputLayout", #code `return null);
    IUnknown_Release(reflector);
    return input_layout;
}


check_hr :: (from: string, code_to_insert_after_fail := #code `return) #expand {
    if FAILED(`hr) {
        fail_message : string;
        // https://learn.microsoft.com/tr-tr/windows/win32/direct3d11/d3d11-graphics-reference-returnvalues
        if `hr == {
        case 0x887C0002; fail_message = "The file was not found.";
        case 0x887C0001; fail_message = "There are too many unique instances of a particular type of state object.";
        case 0x887C0003; fail_message = "There are too many unique instances of a particular type of view object.";
        case 0x887C0004; fail_message = "The first call to ID3D11DeviceContext::Map was not D3D11_MAP_WRITE_DISCARD.";
        case 0x887A0001; fail_message = "The procedure call is invalid.";
        case 0x887A000A; fail_message = "The previous blit operation that is transferring information to or from this surface is incomplete.";

        case 0x80004005; fail_message = "The procedure failed.";
        case 0x80070057; fail_message = "An invalid argument was passed to the procedure.";
        case 0x8007000E; fail_message = "Direct3D could not allocate sufficient memory to complete the call.";
        case 0x80004001; fail_message = "The procedure call isn't implemented with the passed parameter combination.";

        case; fail_message = get_last_error();
        }

        log_error("% failed with code 0x%: %\n", from, FormatInt.{value = `hr, base=16}, fail_message);
        #insert code_to_insert_after_fail;
    }
}

get_last_error :: () -> string {
    error := GetLastError();
    if(error == 0) {
        return ""; //No error message has been recorded
    }

    message_buffer: *u8;
    // Ask Win32 to give us the string version of that message ID.
    // The parameters we pass in, tell Win32 to create the buffer that holds the message for us (because we don't yet know how long the message string will be).
    size := FormatMessageA(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, null, error, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), *message_buffer, 0, null);

    message := string.{data=message_buffer, count=size};

    return message;
}

FrameInfo : struct {
    num_bound_vertices: u32;
    num_bound_indices: u32;
}

D3D11 : struct {
    device: *ID3D11Device;
    device_context: *ID3D11DeviceContext;
    swap_chain: *IDXGISwapChain1;
    render_target_view: *ID3D11RenderTargetView;
    depth_stencil_view: *ID3D11DepthStencilView;

    scissor_state: *ID3D11RasterizerState;
    blend_alpha_state: *ID3D11BlendState;

    msaa : u32;
}
#import "d3d11";
#import "d3d_compiler";
#import "dxgi";
#import "Windows";
Crash_Handler :: #import "Runtime_Support_Crash_Handler";

#if DEBUG {
    init_exception_handler :: () {
        info: *ID3D11InfoQueue;
        hr := IUnknown_QueryInterface(D3D11.device, *uid(ID3D11InfoQueue_UUID), cast(**void) *info);
        if(SUCCEEDED(hr))
        {
            ID3D11InfoQueue_SetBreakOnSeverity(info, .CORRUPTION, 1);
            ID3D11InfoQueue_SetBreakOnSeverity(info, .ERROR, 1);
        }
        IUnknown_Release(info);
        kernel32 :: #system_library "kernel32";
        SetUnhandledExceptionFilter :: (lpTopLevelExceptionFilter: *void) -> *void #foreign kernel32;
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
        IUnknown_QueryInterface(D3D11.device, *uid(ID3D11InfoQueue_UUID), cast(**void) *info);

        message_count := ID3D11InfoQueue_GetNumStoredMessages(info);
        if message_count == 0 return .{}, false;
        logged_ids : [..]D3D11_MESSAGE_ID;
        message_str: string;
        sb: String_Builder;
        error := false;
        for i: 0..message_count-1 {
            message_size : u64;
            ID3D11InfoQueue_GetMessageA(info, i, null, *message_size);

            message := cast(*D3D11_MESSAGE) alloc(xx message_size);
            ID3D11InfoQueue_GetMessageA(info, i, message, *message_size);

            for logged_ids {
                if it == message.ID  continue i;
            }
            array_add(*logged_ids, message.ID);

            if message.Severity == .ERROR || message.Severity == .CORRUPTION {
                error = true;
            }
            message_str = string.{data=message.pDescription, count=xx message.DescriptionByteLength-1};
            log_error("%: %\n", message.ID, message_str);
            free(message);
        }
        ID3D11InfoQueue_ClearStoredMessages(info);
        IUnknown_Release(info);
        return message_str, error;
    }
}
