using System.Threading;
using System.Windows;

namespace ScreenshotApp.Windows;

public partial class App : Application
{
    private Mutex? instance;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        instance = new Mutex(false, @"Local\ScreenshotApp-Bogdan-Windows", out bool firstInstance);
        if (!firstInstance)
        {
            MessageBox.Show("Скриншутер уже открыт. Найдите его на панели задач.", "Скриншутер");
            Shutdown();
            return;
        }

        var home = new MainWindow(new LocalStore());
        MainWindow = home;
        home.Show();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        instance?.Dispose();
        base.OnExit(e);
    }
}
