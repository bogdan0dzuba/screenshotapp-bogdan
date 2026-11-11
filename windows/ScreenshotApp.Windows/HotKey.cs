using System.Windows.Input;
using System.Windows.Interop;

namespace ScreenshotApp.Windows;

internal sealed record HotKey(bool Ctrl, bool Alt, bool Shift, Key Key)
{
    internal static readonly HotKey Default = new(true, false, true, Key.A);
    internal static IEnumerable<Key> Choices =>
        Enum.GetValues<Key>().Where(key => key is >= Key.A and <= Key.Z or >= Key.F1 and <= Key.F11);

    internal bool IsValid => (Ctrl || Alt || Shift) && Choices.Contains(Key);

    internal uint Modifiers => (Alt ? 1u : 0) | (Ctrl ? 2u : 0) | (Shift ? 4u : 0) | 0x4000u;

    public override string ToString() =>
        (Ctrl ? "Ctrl + " : "") + (Alt ? "Alt + " : "") + (Shift ? "Shift + " : "") + Key;
}

internal sealed class HotKeyRegistration : IDisposable
{
    private readonly HwndSource source;
    private readonly Action pressed;
    private int activeId;
    internal HotKey? Current { get; private set; }

    internal HotKeyRegistration(HwndSource source, Action pressed)
    {
        this.source = source;
        this.pressed = pressed;
        source.AddHook(OnMessage);
    }

    internal bool TrySet(HotKey key)
    {
        if (!key.IsValid)
            return false;
        if (key == Current)
            return true;

        // Register the replacement before giving up the working shortcut.
        int nextId = activeId == 1 ? 2 : 1;
        if (!Native.RegisterHotKey(source.Handle, nextId, key.Modifiers,
                (uint)KeyInterop.VirtualKeyFromKey(key.Key)))
            return false;

        if (activeId != 0)
            Native.UnregisterHotKey(source.Handle, activeId);
        activeId = nextId;
        Current = key;
        return true;
    }

    private nint OnMessage(nint window, int message, nint wParam, nint lParam, ref bool handled)
    {
        if (message == Native.HotKeyMessage && activeId != 0 && wParam == activeId)
        {
            handled = true;
            source.Dispatcher.InvokeAsync(pressed);
        }
        return 0;
    }

    public void Dispose()
    {
        if (source.IsDisposed)
            return;
        if (activeId != 0)
            Native.UnregisterHotKey(source.Handle, activeId);
        source.RemoveHook(OnMessage);
        activeId = 0;
        Current = null;
    }
}
