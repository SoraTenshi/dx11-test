const std = @import("std");
const win = @import("zigwin32");
const ui = win.ui.windows_and_messaging;

const dxgi = win.graphics.dxgi;
const dx = win.graphics.direct3d11;
const d3d = win.graphics.direct3d;

const L = win.zig.L;

const w = std.os.windows;
const HINSTANCE = w.HINSTANCE;
const LPWSTR = w.LPWSTR;
const INT = w.INT;
const UINT = w.UINT;
const WNDCLASSEX = ui.WNDCLASSEXW;
const RECT = w.RECT;
const BOOL = w.BOOL;
const HDC = w.HDC;
const HWND = win.foundation.HWND;

const dxgic = dxgi.common;

const WINAPI = w.WINAPI;

var wnd: HWND = undefined;
const wnd_title = L("BaseDX11");
var wnd_size: RECT = .{ .left = 0, .top = 0, .right = 1280, .bottom = 720 };
var wnd_dc: HDC = undefined;
var wnd_dpi: w.UINT = 0;
var wnd_hRC: w.HGLRC = undefined;

var g_width: INT = 1280;
var g_height: INT = 720;
var g_ResizeWidth: UINT = 0;
var g_ResizeHeight: UINT = 0;
var g_pd3dDevice: ?*dx.ID3D11Device = null;
var g_pd3dDeviceContext: ?*dx.ID3D11DeviceContext = null;
var g_pSwapChain: ?*dxgi.IDXGISwapChain = null;
var g_mainRenderTargetView: ?*dx.ID3D11RenderTargetView = null;
var g_pVertexShader: ?*dx.ID3D11VertexShader = null;
var g_pPixelShader: ?*dx.ID3D11PixelShader = null;
var g_pVertexLayout: ?*dx.ID3D11InputLayout = null;
var g_pVertexBuffer: ?*dx.ID3D11Buffer = null;
// below leaks memory, i just don't care for now.
var g_pTextureView: ?*dx.ID3D11ShaderResourceView = null;
var g_pTexture2D: ?*dx.ID3D11Texture2D = null;
var g_pSamplerState: ?*dx.ID3D11SamplerState = null;

const XMFLOAT2 = struct { x: f32, y: f32 };
const XMFLOAT3 = struct { x: f32, y: f32, z: f32 };
const XMFLOAT4 = struct { r: f32, g: f32, b: f32, a: f32 };
const SimpleVertex = struct { position: XMFLOAT3, color: XMFLOAT4, texcoord: XMFLOAT2 };

fn createWindow(hInstance: HINSTANCE) void {
    const wnd_class: WNDCLASSEX = .{
        .cbSize = @sizeOf(WNDCLASSEX),
        .style = .{ .DBLCLKS = 1, .OWNDC = 1 },
        .lpfnWndProc = windowProc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = hInstance,
        .hIcon = null,
        .hCursor = ui.LoadCursorW(null, ui.IDC_ARROW),
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = @ptrCast(wnd_title),
        .hIconSm = null,
    };
    std.debug.print("register class: {x}\n", .{ui.RegisterClassExW(&wnd_class)});
    var overlap = ui.WS_OVERLAPPEDWINDOW;
    std.debug.print("adjust window rect: {x}\n", .{ui.AdjustWindowRectEx(@ptrCast(&wnd_size), overlap, w.FALSE, .{ .APPWINDOW = 1, .WINDOWEDGE = 1 })});
    overlap.VISIBLE = 1;
    wnd = ui.CreateWindowExW(.{ .APPWINDOW = 1, .WINDOWEDGE = 1 }, wnd_title, wnd_title, overlap, ui.CW_USEDEFAULT, ui.CW_USEDEFAULT, 0, 0, null, null, hInstance, null) orelse {
        std.debug.print("This didn't do anything\n", .{});
        std.process.exit(1);
    };

    wnd_dc = GetDC(wnd).?;
    const dpi = GetDpiForWindow(wnd);
    const xcenter = @divFloor(GetSystemMetricsForDpi(@intFromEnum(ui.SM_CXSCREEN), dpi), 2);
    const ycenter = @divFloor(GetSystemMetricsForDpi(@intFromEnum(ui.SM_CYSCREEN), dpi), 2);
    wnd_size.left = xcenter - @divFloor(g_width, 2);
    wnd_size.top = ycenter - @divFloor(g_height, 2);
    wnd_size.right = wnd_size.left + @divFloor(g_width, 2);
    wnd_size.bottom = wnd_size.top + @divFloor(g_height, 2);
    _ = ui.SetWindowPos(wnd, null, wnd_size.left, wnd_size.top, wnd_size.right, wnd_size.bottom, ui.SWP_NOCOPYBITS);
}

fn windowProc(hwnd: HWND, umsg: UINT, wparam: w.WPARAM, lparam: w.LPARAM) callconv(WINAPI) w.LRESULT {
    switch (umsg) {
        ui.WM_DESTROY => {
            ui.PostQuitMessage(0);
            return 0;
        },
        ui.WM_PAINT => {
            var ps: win.graphics.gdi.PAINTSTRUCT = undefined;
            const hdc: HDC = BeginPaint(hwnd, &ps) orelse undefined;
            _ = FillRect(hdc, @ptrCast(&ps.rcPaint), @ptrFromInt(@intFromEnum(ui.COLOR_WINDOW) + 1));
            _ = EndPaint(hwnd, &ps);
        },
        ui.WM_SIZE => {
            g_ResizeWidth = loword(lparam);
            g_ResizeHeight = hiword(lparam);
        },
        ui.WM_KEYDOWN, ui.WM_SYSKEYDOWN => {
            switch (wparam) {
                @intFromEnum(win.ui.input.keyboard_and_mouse.VK_ESCAPE) => { //SHIFT+ESC = EXIT
                    if (GetAsyncKeyState(@intFromEnum(win.ui.input.keyboard_and_mouse.VK_LSHIFT)) & 0x01 == 1) {
                        ui.PostQuitMessage(0);
                        return 0;
                    }
                },
                else => {},
            }
        },
        else => _ = .{},
    }

    return ui.DefWindowProcW(hwnd, umsg, wparam, lparam);
}

pub export fn wWinMain(instance: HINSTANCE, prev_instance: ?HINSTANCE, cmd_line: ?LPWSTR, cmd_show: INT) callconv(WINAPI) INT {
    _ = prev_instance; // autofix
    _ = cmd_line; // autofix
    createWindow(instance);
    defer _ = ReleaseDC(wnd, wnd_dc);
    defer _ = UnregisterClassW(wnd_title, instance);
    defer _ = DestroyWindow(wnd);

    if (!createDeviceD3D(wnd)) {
        cleanupDeviceD3D();
        return 1;
    }

    _ = ShowWindow(wnd, cmd_show);
    _ = UpdateWindow(wnd);

    var clear_color = [_]f32{ 0.345, 0.345, 0.345, 1.0 };
    var done = false;
    var msg: ui.MSG = std.mem.zeroes(ui.MSG);
    while (!done) {
        while (PeekMessageA(&msg, null, 0, 0, PM_REMOVE) != 0) {
            _ = TranslateMessage(&msg);
            _ = DispatchMessageW(&msg);
            if (msg.message == ui.WM_QUIT) {
                done = true;
            }
        }
        if (done) break;

        if (g_ResizeWidth != 0 and g_ResizeHeight != 0) {
            cleanupRenderTarget();
            _ = g_pSwapChain.?.vtable.ResizeBuffers(g_pSwapChain.?, 0, g_ResizeWidth, g_ResizeHeight, dxgic.DXGI_FORMAT_UNKNOWN, 0);
            g_ResizeWidth = 0;
            g_ResizeHeight = 0;
            createRenderTarget();
        }

        g_pd3dDeviceContext.?.vtable.OMSetRenderTargets(g_pd3dDeviceContext.?, 1, @ptrCast(&g_mainRenderTargetView), null);
        g_pd3dDeviceContext.?.vtable.ClearRenderTargetView(g_pd3dDeviceContext.?, g_mainRenderTargetView, @ptrCast((&clear_color).ptr));

        g_pd3dDeviceContext.?.vtable.VSSetShader(g_pd3dDeviceContext.?, g_pVertexShader, null, 0);
        g_pd3dDeviceContext.?.vtable.PSSetShader(g_pd3dDeviceContext.?, g_pPixelShader, null, 0);
        g_pd3dDeviceContext.?.vtable.PSSetShaderResources(g_pd3dDeviceContext.?, 0, 1, @ptrCast(&g_pTextureView));
        g_pd3dDeviceContext.?.vtable.PSSetSamplers(g_pd3dDeviceContext.?, 0, 1, @ptrCast(&g_pSamplerState));
        g_pd3dDeviceContext.?.vtable.Draw(g_pd3dDeviceContext.?, 6, 0);

        _ = g_pSwapChain.?.vtable.Present(g_pSwapChain.?, 0, 0);
    }

    cleanupDeviceD3D();
    return 0;
}

// DIRECTX 11
fn createDeviceD3D(hWnd: HWND) bool {
    var rc: RECT = undefined;
    _ = GetClientRect(hWnd, &rc);
    const width: UINT = @as(c_uint, @intCast(rc.right - rc.left));
    const height: UINT = @as(c_uint, @intCast(rc.bottom - rc.top));

    var sd = std.mem.zeroes(dxgi.DXGI_SWAP_CHAIN_DESC);
    sd.BufferCount = 6;
    sd.BufferDesc.Width = width;
    sd.BufferDesc.Height = height;
    sd.BufferDesc.Format = dxgic.DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferDesc.RefreshRate.Numerator = 60;
    sd.BufferDesc.RefreshRate.Denominator = 1;
    sd.Flags = @intFromEnum(dxgi.DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH);
    sd.BufferUsage = dxgi.DXGI_USAGE_RENDER_TARGET_OUTPUT;
    @setRuntimeSafety(false);
    sd.OutputWindow = @as(HWND, @alignCast(@ptrCast(hWnd)));
    @setRuntimeSafety(true);
    sd.SampleDesc.Count = 1;
    sd.SampleDesc.Quality = 0;
    sd.Windowed = w.TRUE;
    sd.SwapEffect = dxgi.DXGI_SWAP_EFFECT_DISCARD;

    const createDeviceFlags: dx.D3D11_CREATE_DEVICE_FLAG = .{
        .DEBUG = 1,
    };
    //createDeviceFlags |= D3D11_CREATE_DEVICE_DEBUG;
    var featureLevel: d3d.D3D_FEATURE_LEVEL = undefined;
    const featureLevelArray = &[_]d3d.D3D_FEATURE_LEVEL{ d3d.D3D_FEATURE_LEVEL_11_0, d3d.D3D_FEATURE_LEVEL_10_0 };
    var res: win.foundation.HRESULT = dx.D3D11CreateDeviceAndSwapChain(
        null,
        d3d.D3D_DRIVER_TYPE_HARDWARE,
        null,
        createDeviceFlags,
        featureLevelArray,
        2,
        dx.D3D11_SDK_VERSION,
        &sd,
        &g_pSwapChain,
        &g_pd3dDevice,
        &featureLevel,
        &g_pd3dDeviceContext,
    );

    if (res == dxgi.DXGI_ERROR_UNSUPPORTED) { // Try high-performance WARP software driver if hardware is not available.
        res = dx.D3D11CreateDeviceAndSwapChain(
            null,
            d3d.D3D_DRIVER_TYPE_WARP,
            null,
            createDeviceFlags,
            featureLevelArray,
            2,
            dx.D3D11_SDK_VERSION,
            &sd,
            &g_pSwapChain,
            &g_pd3dDevice,
            &featureLevel,
            &g_pd3dDeviceContext,
        );
    }
    if (res != win.foundation.S_OK)
        return false;

    createRenderTarget();
    g_pd3dDeviceContext.?.vtable.OMSetRenderTargets(g_pd3dDeviceContext.?, 1, @ptrCast(&g_mainRenderTargetView), null);

    var vp: dx.D3D11_VIEWPORT = undefined;
    vp.Width = @as(f32, @floatFromInt(width));
    vp.Height = @as(f32, @floatFromInt(height));
    vp.MinDepth = 0.0;
    vp.MaxDepth = 1.0;
    vp.TopLeftX = 0;
    vp.TopLeftY = 0;
    g_pd3dDeviceContext.?.vtable.RSSetViewports(g_pd3dDeviceContext.?, 1, @ptrCast(&vp));

    var pVSBlob: ?*d3d.ID3DBlob = null;
    var error_message: ?*d3d.ID3DBlob = null;
    const compile_shader = d3d.fxc.D3DCompileFromFile(
        L("shaders.hlsl"),
        null,
        null,
        "VSMain",
        "vs_4_0",
        d3d.fxc.D3DCOMPILE_ENABLE_STRICTNESS,
        0,
        &pVSBlob,
        &error_message,
    );
    if (compile_shader != win.foundation.S_OK) {
        defer error_message.?.base.Release(error_message.?);
        const as_str: [*:0]const u8 = @ptrCast(error_message.?.vtable.GetBufferPointer(error_message.?));
        std.debug.print("vertex shader compilation failed with:\n{s}\n", .{as_str});
        std.process.exit(1);
    }

    _ = g_pd3dDevice.?.vtable.CreateVertexShader(
        g_pd3dDevice.?,
        @ptrCast(pVSBlob.?.vtable.GetBufferPointer(pVSBlob.?)),
        pVSBlob.?.vtable.GetBufferSize(pVSBlob.?),
        null,
        &g_pVertexShader,
    );

    const input_layout_desc = &[_]dx.D3D11_INPUT_ELEMENT_DESC{
        .{ .SemanticName = "POSITION", .SemanticIndex = 0, .Format = dxgic.DXGI_FORMAT_R32G32B32_FLOAT, .InputSlot = 0, .AlignedByteOffset = 0, .InputSlotClass = dx.D3D11_INPUT_PER_VERTEX_DATA, .InstanceDataStepRate = 0 },
        .{ .SemanticName = "COLOR", .SemanticIndex = 0, .Format = dxgic.DXGI_FORMAT_R32G32B32A32_FLOAT, .InputSlot = 0, .AlignedByteOffset = 12, .InputSlotClass = dx.D3D11_INPUT_PER_VERTEX_DATA, .InstanceDataStepRate = 0 },
        .{ .SemanticName = "TEXCOORD", .SemanticIndex = 0, .Format = dxgic.DXGI_FORMAT_R32G32_FLOAT, .InputSlot = 0, .AlignedByteOffset = 28, .InputSlotClass = dx.D3D11_INPUT_PER_VERTEX_DATA, .InstanceDataStepRate = 0 },
    };
    const numElements: UINT = input_layout_desc.len;
    _ = g_pd3dDevice.?.vtable.CreateInputLayout(g_pd3dDevice.?, input_layout_desc, numElements, @ptrCast(pVSBlob.?.vtable.GetBufferPointer(pVSBlob.?)), pVSBlob.?.vtable.GetBufferSize(pVSBlob.?), &g_pVertexLayout);
    _ = pVSBlob.?.vtable.base.Release(@ptrCast(pVSBlob.?));
    g_pd3dDeviceContext.?.vtable.IASetInputLayout(g_pd3dDeviceContext.?, g_pVertexLayout);

    var vertices = [_]SimpleVertex{
        .{
            .position = XMFLOAT3{ .x = -0.45, .y = 0.5, .z = 0.0 },
            .color = XMFLOAT4{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 },
            .texcoord = XMFLOAT2{ .x = 1.0, .y = 0.0 },
        },
        .{
            .position = XMFLOAT3{ .x = 0.45, .y = 0.5, .z = 0.0 },
            .color = XMFLOAT4{ .r = 0.0, .g = 1.0, .b = 0.0, .a = 1.0 },
            .texcoord = XMFLOAT2{ .x = 1.0, .y = 0.0 },
        },
        .{
            .position = XMFLOAT3{ .x = -0.45, .y = -0.5, .z = 0.0 },
            .color = XMFLOAT4{ .r = 0.0, .g = 0.0, .b = 1.0, .a = 1.0 },
            .texcoord = XMFLOAT2{ .x = 1.0, .y = 0.0 },
        },
        .{
            .position = XMFLOAT3{ .x = 0.45, .y = -0.5, .z = 0.0 },
            .color = XMFLOAT4{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 },
            .texcoord = XMFLOAT2{ .x = 0.0, .y = 1.0 },
        },
        .{
            .position = XMFLOAT3{ .x = -0.45, .y = -0.5, .z = 0.0 },
            .color = XMFLOAT4{ .r = 0.0, .g = 0.0, .b = 1.0, .a = 1.0 },
            .texcoord = XMFLOAT2{ .x = 0.0, .y = 1.0 },
        },
        .{
            .position = XMFLOAT3{ .x = 0.45, .y = 0.5, .z = 0.0 },
            .color = XMFLOAT4{ .r = 0.0, .g = 1.0, .b = 0.0, .a = 1.0 },
            .texcoord = XMFLOAT2{ .x = 0.0, .y = 1.0 },
        },
    };
    var bd: dx.D3D11_BUFFER_DESC = std.mem.zeroes(dx.D3D11_BUFFER_DESC);
    bd.Usage = dx.D3D11_USAGE_DEFAULT;
    bd.ByteWidth = @sizeOf(SimpleVertex) * vertices.len;
    bd.BindFlags = dx.D3D11_BIND_VERTEX_BUFFER;
    bd.CPUAccessFlags = .{};
    var InitData: dx.D3D11_SUBRESOURCE_DATA = undefined;
    InitData.pSysMem = &vertices;
    _ = g_pd3dDevice.?.vtable.CreateBuffer(g_pd3dDevice.?, &bd, &InitData, &g_pVertexBuffer);
    var stride: UINT = @sizeOf(SimpleVertex);
    var offset: UINT = 0;
    g_pd3dDeviceContext.?.vtable.IASetVertexBuffers(g_pd3dDeviceContext.?, 0, 1, @ptrCast(&g_pVertexBuffer), @ptrCast(&stride), @ptrCast(&offset));
    g_pd3dDeviceContext.?.vtable.IASetPrimitiveTopology(g_pd3dDeviceContext.?, d3d.D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

    var t2dd: dx.D3D11_TEXTURE2D_DESC = std.mem.zeroes(dx.D3D11_TEXTURE2D_DESC);
    t2dd = .{
        .Width = 2,
        .Height = 2,
        .MipLevels = 1,
        .ArraySize = 1,
        .Format = dxgic.DXGI_FORMAT.R8G8B8A8_UNORM,
        .SampleDesc = .{
            .Count = 1,
            .Quality = 0,
        },
        .Usage = dx.D3D11_USAGE_DEFAULT,
        .BindFlags = dx.D3D11_BIND_SHADER_RESOURCE,
        .CPUAccessFlags = .{},
        .MiscFlags = .{},
    };

    var resource_data: dx.D3D11_SUBRESOURCE_DATA = std.mem.zeroes(dx.D3D11_SUBRESOURCE_DATA);
    const texture_data = [2 * 2]UINT{ 0xFFFF00FF, 0xFFFF0000, 0xFF0000FF, 0xFF0000FF };
    resource_data.pSysMem = &texture_data;
    resource_data.SysMemPitch = 2 * 2 * 4;

    const result = g_pd3dDevice.?.vtable.CreateTexture2D(
        g_pd3dDevice.?,
        &t2dd,
        &resource_data,
        &g_pTexture2D,
    );

    if (result != win.foundation.S_OK) {
        std.debug.print("Texture2D could not be created, exiting...\n", .{});
        std.process.exit(1);
    }

    var rvd: dx.D3D11_SHADER_RESOURCE_VIEW_DESC = std.mem.zeroes(dx.D3D11_SHADER_RESOURCE_VIEW_DESC);
    rvd = .{
        .Format = dxgic.DXGI_FORMAT.R8G8B8A8_UNORM,
        .ViewDimension = @enumFromInt(4), // DIMENSION_TEXTURE2D
        .Anonymous = .{ .Texture2D = .{
            .MostDetailedMip = 0,
            .MipLevels = 1,
        } },
    };

    const rv_result = g_pd3dDevice.?.vtable.CreateShaderResourceView(
        g_pd3dDevice.?,
        &g_pTexture2D.?.ID3D11Resource,
        &rvd,
        &g_pTextureView,
    );

    if (rv_result != win.foundation.S_OK) {
        std.debug.print("ShaderResourceView could not be created\n", .{});
        std.process.exit(1);
    }

    var pPSBlob: ?*d3d.ID3DBlob = null;
    const ps_res = d3d.fxc.D3DCompileFromFile(
        L("shaders.hlsl"),
        null,
        null,
        "PSMain",
        "ps_4_0",
        d3d.fxc.D3DCOMPILE_ENABLE_STRICTNESS,
        0,
        &pPSBlob,
        null,
    );

    if (ps_res != win.foundation.S_OK) {
        std.debug.print("pixel shader compilation failed\n", .{});
        std.process.exit(1);
    }

    _ = g_pd3dDevice.?.vtable.CreatePixelShader(g_pd3dDevice.?, @ptrCast(pPSBlob.?.vtable.GetBufferPointer(pPSBlob.?)), pPSBlob.?.vtable.GetBufferSize(pPSBlob.?), null, &g_pPixelShader);
    _ = pPSBlob.?.vtable.base.Release(@ptrCast(pPSBlob.?));

    var samp_desc: dx.D3D11_SAMPLER_DESC = std.mem.zeroes(dx.D3D11_SAMPLER_DESC);
    samp_desc.Filter = dx.D3D11_FILTER.MIN_MAG_MIP_LINEAR;
    samp_desc.AddressU = dx.D3D11_TEXTURE_ADDRESS_MODE.WRAP;
    samp_desc.AddressV = dx.D3D11_TEXTURE_ADDRESS_MODE.WRAP;
    samp_desc.AddressW = dx.D3D11_TEXTURE_ADDRESS_MODE.WRAP;

    const sampler = g_pd3dDevice.?.vtable.CreateSamplerState(g_pd3dDevice.?, &samp_desc, &g_pSamplerState);
    if (sampler != win.foundation.S_OK) {
        std.debug.print("sampler state could not be iniitialized\n", .{});
        std.process.exit(1);
    }

    return true;
}

fn cleanupDeviceD3D() void {
    cleanupRenderTarget();
    _ = g_pSwapChain.?.vtable.base.base.base.Release(@ptrCast(g_pSwapChain.?));
    _ = g_pd3dDeviceContext.?.vtable.base.base.Release(@ptrCast(g_pd3dDeviceContext.?));
    _ = g_pd3dDevice.?.vtable.base.Release(@ptrCast(g_pd3dDevice.?));
    g_pVertexBuffer = null;
    g_pVertexLayout = null;
    g_pVertexShader = null;
    g_pPixelShader = null;
    g_pSwapChain = null;
    g_pd3dDeviceContext = null;
    g_pd3dDevice = null;
}

fn createRenderTarget() void {
    var pBackBuffer: ?*dx.ID3D11Texture2D = null;

    _ = g_pSwapChain.?.vtable.GetBuffer(g_pSwapChain.?, 0, dx.IID_ID3D11Texture2D, @as([*c]?*anyopaque, @ptrCast(&pBackBuffer)));
    _ = g_pd3dDevice.?.vtable.CreateRenderTargetView(
        g_pd3dDevice.?,
        @as([*c]dx.ID3D11Resource, @ptrCast(pBackBuffer.?)),
        null,
        &g_mainRenderTargetView,
    );
    _ = pBackBuffer.?.vtable.base.base.base.Release(@ptrCast(pBackBuffer.?));
}

fn cleanupRenderTarget() void {
    if (g_mainRenderTargetView) |mRTV| {
        _ = mRTV.vtable.base.base.base.Release(@ptrCast(g_mainRenderTargetView.?));
        g_mainRenderTargetView = null;
    }
}

fn loword(l: w.LONG_PTR) UINT {
    return @as(u32, @intCast(l)) & 0xFFFF;
}
fn hiword(l: w.LONG_PTR) UINT {
    return (@as(u32, @intCast(l)) >> 16) & 0xFFFF;
}

pub extern "user32" fn BeginPaint(
    hWnd: ?HWND,
    lpPaint: ?*win.graphics.gdi.PAINTSTRUCT,
) callconv(WINAPI) ?HDC;

pub extern "user32" fn FillRect(hDC: ?HDC, lprc: ?*const RECT, hbr: ?win.graphics.gdi.HBRUSH) callconv(WINAPI) INT;

pub extern "user32" fn EndPaint(hWnd: HWND, lpPaint: *const win.graphics.gdi.PAINTSTRUCT) callconv(WINAPI) BOOL;

pub extern "gdi32" fn TextOutW(hDC: ?HDC, x: INT, y: INT, lpString: w.LPCWSTR, c: w.INT) callconv(WINAPI) BOOL;

pub extern "user32" fn GetAsyncKeyState(nKey: c_int) callconv(WINAPI) w.INT;

const IDC_ARROW: w.LONG = 32512;
pub extern "user32" fn LoadCursorW(
    hInstance: ?w.HINSTANCE,
    lpCursorName: w.LONG,
) callconv(WINAPI) w.HCURSOR;

pub extern "kernel32" fn OutputDebugStringA(lpOutputString: w.LPCSTR) callconv(WINAPI) w.INT;

pub extern "user32" fn GetWindowRect(hWnd: HWND, lpRect: *ui.RECT) callconv(WINAPI) w.INT;

pub const SM_CXSCREEN = 0;
pub const SM_CYSCREEN = 1;
pub extern "user32" fn GetSystemMetricsForDpi(nIndex: w.INT, dpi: w.UINT) callconv(WINAPI) w.INT;

pub extern "user32" fn GetDpiForWindow(
    hWnd: HWND,
) callconv(WINAPI) w.UINT;

pub const SWP_NOCOPYBITS = 0x0100;
pub extern "user32" fn SetWindowPos(
    hWnd: HWND,
    hWndInsertAfter: ?HWND,
    X: w.INT,
    Y: w.INT,
    cx: w.INT,
    cy: w.INT,
    uFlags: w.UINT,
) callconv(WINAPI) BOOL;

pub extern "user32" fn GetClientRect(hWnd: HWND, lpRect: *RECT) callconv(WINAPI) w.UINT;

pub extern "user32" fn DestroyWindow(hWnd: HWND) callconv(WINAPI) BOOL;

pub extern "user32" fn UnregisterClassW(lpClassName: [*:0]const u16, hInstance: w.HINSTANCE) callconv(WINAPI) BOOL;

pub extern "user32" fn ReleaseDC(hWnd: ?HWND, hDC: w.HDC) callconv(WINAPI) i32;

pub extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: i32) callconv(WINAPI) BOOL;

pub extern "user32" fn UpdateWindow(hWnd: HWND) callconv(WINAPI) BOOL;

pub const PM_REMOVE = 0x0001;
pub extern "user32" fn PeekMessageA(lpMsg: *ui.MSG, hWnd: ?HWND, wMsgFilterMin: w.UINT, wMsgFilterMax: w.UINT, wRemoveMsg: w.UINT) callconv(WINAPI) BOOL;
pub extern "user32" fn TranslateMessage(lpMsg: *const ui.MSG) callconv(WINAPI) BOOL;
pub extern "user32" fn DispatchMessageW(lpMsg: *const ui.MSG) callconv(WINAPI) w.LRESULT;
pub extern "user32" fn PostQuitMessage(nExitCode: i32) callconv(WINAPI) void;
pub extern "user32" fn RegisterClassExW(*const WNDCLASSEX) callconv(WINAPI) w.ATOM;
pub extern "user32" fn AdjustWindowRectEx(lpRect: *RECT, dwStyle: w.DWORD, bMenu: BOOL, dwExStyle: w.DWORD) callconv(WINAPI) BOOL;
pub extern "user32" fn CreateWindowExW(dwExStyle: w.DWORD, lpClassName: [*:0]const u16, lpWindowName: [*:0]const u16, dwStyle: w.DWORD, X: i32, Y: i32, nWidth: i32, nHeight: i32, hWindParent: ?HWND, hMenu: ?w.HMENU, hInstance: w.HINSTANCE, lpParam: ?w.LPVOID) callconv(WINAPI) ?HWND;
pub extern "user32" fn DefWindowProcW(hWnd: HWND, Msg: w.UINT, wParam: w.WPARAM, lParam: w.LPARAM) callconv(WINAPI) w.LRESULT;
pub extern "user32" fn GetDC(hWnd: ?HWND) callconv(WINAPI) ?w.HDC;
