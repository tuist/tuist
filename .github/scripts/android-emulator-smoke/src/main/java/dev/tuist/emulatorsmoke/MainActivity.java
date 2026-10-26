package dev.tuist.emulatorsmoke;

import android.app.Activity;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.os.Bundle;
import android.os.SystemClock;
import android.util.Log;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;

public final class MainActivity extends Activity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        setContentView(new DemoView());
    }

    private final class DemoView extends View {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final long started = SystemClock.uptimeMillis();
        private int taps;

        DemoView() {
            super(MainActivity.this);
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            float width = getWidth();
            float height = getHeight();
            float elapsed = (SystemClock.uptimeMillis() - started) / 1000f;
            canvas.drawColor(Color.rgb(24, 24, 40));
            paint.setTextAlign(Paint.Align.CENTER);
            paint.setColor(Color.WHITE);
            paint.setTextSize(width / 16f);
            canvas.drawText("Android on Tuist macOS", width / 2, height / 5, paint);
            paint.setTextSize(width / 22f);
            canvas.drawText("Tap anywhere", width / 2, height / 5 + width / 10, paint);
            canvas.drawText("Taps: " + taps, width / 2, height * 0.8f, paint);
            paint.setColor(Color.rgb(170, 130, 255));
            float x = width / 2 + (float) Math.sin(elapsed * 2) * width / 4;
            float y = height / 2 + (float) Math.cos(elapsed * 2) * height / 10;
            canvas.drawCircle(x, y, width / 12, paint);
            postInvalidateOnAnimation();
        }

        @Override
        public boolean onTouchEvent(MotionEvent event) {
            if (event.getAction() == MotionEvent.ACTION_UP) {
                performClick();
            }
            return true;
        }

        @Override
        public boolean performClick() {
            super.performClick();
            taps++;
            Log.i("TuistSmoke", "SMOKE_TAPS=" + taps);
            invalidate();
            return true;
        }
    }
}
