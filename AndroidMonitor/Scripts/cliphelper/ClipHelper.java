import android.content.ClipData;
import android.os.IBinder;
import android.os.Looper;
import android.util.Base64;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.lang.reflect.Method;

/** Runs on the phone via app_process (shell uid). Line protocol on stdin: "G" -> "G <base64>", "S <base64>" -> "OK". */
public final class ClipHelper {
    private static final String PACKAGE = "com.android.shell";
    private static Object service;

    public static void main(String[] args) throws Exception {
        try { Looper.prepareMainLooper(); } catch (Throwable ignored) { }
        Class<?> serviceManager = Class.forName("android.os.ServiceManager");
        IBinder binder = (IBinder) serviceManager.getMethod("getService", String.class).invoke(null, "clipboard");
        service = Class.forName("android.content.IClipboard$Stub").getMethod("asInterface", IBinder.class).invoke(null, binder);

        BufferedReader in = new BufferedReader(new InputStreamReader(System.in));
        String line;
        while ((line = in.readLine()) != null) {
            try {
                if (line.equals("G")) {
                    System.out.println("G " + Base64.encodeToString(get().getBytes("UTF-8"), Base64.NO_WRAP));
                } else if (line.startsWith("S ")) {
                    set(new String(Base64.decode(line.substring(2), Base64.NO_WRAP), "UTF-8"));
                    System.out.println("OK");
                } else {
                    System.out.println("ERR unknown");
                }
            } catch (Throwable t) {
                Throwable cause = t.getCause() != null ? t.getCause() : t;
                System.out.println("ERR " + cause.getClass().getSimpleName() + ":" + String.valueOf(cause.getMessage()).replace('\n', ' '));
            }
            System.out.flush();
        }
    }

    private static String get() throws Exception {
        Method method = find("getPrimaryClip");
        Object clip = method.invoke(service, arguments(method, null));
        if (clip == null) return "";
        ClipData data = (ClipData) clip;
        if (data.getItemCount() == 0) return "";
        CharSequence text = data.getItemAt(0).getText();
        return text == null ? "" : text.toString();
    }

    private static void set(String text) throws Exception {
        Method method = find("setPrimaryClip");
        method.invoke(service, arguments(method, ClipData.newPlainText("android-monitor", text)));
    }

    private static Method find(String name) throws Exception {
        for (Method m : service.getClass().getMethods()) if (m.getName().equals(name)) return m;
        throw new NoSuchMethodException(name);
    }

    /** Signatures differ per Android release (pkg, attributionTag, userId, deviceId); fill by parameter type. */
    private static Object[] arguments(Method method, ClipData clip) {
        Class<?>[] types = method.getParameterTypes();
        Object[] values = new Object[types.length];
        boolean packageSet = false;
        for (int i = 0; i < types.length; i++) {
            if (types[i] == ClipData.class) values[i] = clip;
            else if (types[i] == String.class) { values[i] = packageSet ? null : PACKAGE; packageSet = true; }
            else if (types[i] == int.class) values[i] = 0;
        }
        return values;
    }
}
