import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.Drawable;
import android.os.Looper;
import android.util.Base64;
import java.io.ByteArrayOutputStream;
import java.lang.reflect.Method;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/** Runs on the phone via app_process; prints one tab-separated line per launchable app: pkg, label, flags, version, icon(png base64). */
public final class AppsHelper {
    private static final int ICON_SIZE = 96;

    public static void main(String[] args) throws Exception {
        try { Looper.prepareMainLooper(); } catch (Throwable ignored) { }
        Class<?> thread = Class.forName("android.app.ActivityThread");
        Object at = thread.getMethod("systemMain").invoke(null);
        Context context = (Context) thread.getMethod("getSystemContext").invoke(at);
        PackageManager pm = context.getPackageManager();

        Intent launcher = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER);
        List<ResolveInfo> apps = pm.queryIntentActivities(launcher, 0);
        Set<String> seen = new HashSet<>();
        for (ResolveInfo info : apps) {
            ApplicationInfo app = info.activityInfo.applicationInfo;
            if (!seen.add(app.packageName)) continue;
            try {
                String label = String.valueOf(info.loadLabel(pm));
                String version = "";
                try { PackageInfo pi = pm.getPackageInfo(app.packageName, 0); if (pi.versionName != null) version = pi.versionName; } catch (Throwable ignored) { }
                String flags = ((app.flags & ApplicationInfo.FLAG_SYSTEM) != 0 ? "S" : "U") + ((app.flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0 ? "D" : "");
                String icon = "";
                try { icon = png(info.loadIcon(pm)); } catch (Throwable ignored) { }
                System.out.println(app.packageName + "\t" + b64(label) + "\t" + flags + "\t" + b64(version) + "\t" + icon);
                System.out.flush();
            } catch (Throwable ignored) { }
        }
    }

    private static String b64(String value) throws Exception {
        return Base64.encodeToString(value.getBytes("UTF-8"), Base64.NO_WRAP);
    }

    private static String png(Drawable drawable) {
        Bitmap bitmap = Bitmap.createBitmap(ICON_SIZE, ICON_SIZE, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bitmap);
        drawable.setBounds(0, 0, ICON_SIZE, ICON_SIZE);
        drawable.draw(canvas);
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out);
        return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP);
    }
}
