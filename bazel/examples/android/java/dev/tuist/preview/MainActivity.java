package dev.tuist.preview;

public final class MainActivity extends android.app.Activity {
    @Override
    public void onCreate(android.os.Bundle state) {
        super.onCreate(state);
        android.widget.TextView text = new android.widget.TextView(this);
        text.setText("Tuist Bazel Preview");
        setContentView(text);
    }
}
