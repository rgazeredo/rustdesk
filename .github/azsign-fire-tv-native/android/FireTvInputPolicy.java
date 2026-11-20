package com.carriez.flutter_hbb;

/** Pure policy shared by hardware gate and tests; no Android initialization. */
final class FireTvInputPolicy {
    static boolean supported(String manufacturer, String model, int sdk) {
        return sdk == 30 && "Amazon".equalsIgnoreCase(manufacturer) && "AFTHY7ABBA".equalsIgnoreCase(model);
    }
    static String navigation(int code) {
        switch (code) {
            case 19: return "dpad_up";
            case 20: return "dpad_down";
            case 21: return "dpad_left";
            case 22: return "dpad_right";
            case 23: case 66: case 160: return "select";
            default: return null;
        }
    }
}
