package dyc.dev.isle_log;

import android.view.WindowManager;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(
            flutterEngine.getDartExecutor().getBinaryMessenger(),
            "islelog/screen_guard"
        ).setMethodCallHandler((call, result) -> {
            switch (call.method) {
                case "enable":
                    getWindow().setFlags(
                        WindowManager.LayoutParams.FLAG_SECURE,
                        WindowManager.LayoutParams.FLAG_SECURE
                    );
                    result.success(null);
                    break;
                case "disable":
                    getWindow().clearFlags(WindowManager.LayoutParams.FLAG_SECURE);
                    result.success(null);
                    break;
                default:
                    result.notImplemented();
            }
        });
    }
}
