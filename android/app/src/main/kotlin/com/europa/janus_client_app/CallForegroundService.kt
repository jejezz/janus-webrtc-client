package com.europa.janus_client_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * 통화가 살아 있는 동안 앱을 포그라운드로 붙잡아 두는 서비스.
 *
 * 안드로이드 11+ 는 포그라운드가 아닌 앱의 녹음을 막는다. 통화 중에 홈으로
 * 나가면 마이크가 조용히 침묵 처리되고(logcat: "App op 27 missing, silencing
 * record") 상대는 아무 소리도 못 듣는다. 화면을 벗어나도 통화가 유지되려면
 * foregroundServiceType=microphone 인 서비스가 떠 있어야 한다.
 *
 * 통화 중에만 띄운다. 마이크를 쓰지 않는 동안 마이크 유형 서비스를 붙잡고 있는
 * 것은 정책상으로도 맞지 않는다.
 */
class CallForegroundService : Service() {

    companion object {
        private const val CHANNEL_ID = "janus_call"
        private const val NOTIFICATION_ID = 1001
        const val EXTRA_PEER = "peer"

        fun start(context: Context, peer: String?) {
            val intent = Intent(context, CallForegroundService::class.java)
                .putExtra(EXTRA_PEER, peer)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CallForegroundService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createChannel()
        val notification = buildNotification(intent?.getStringExtra(EXTRA_PEER))

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // 유형을 붙여야 통화 중에도 마이크 접근이 유지된다.
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        // 시스템이 죽여도 되살리지 않는다. 통화는 앱이 다시 시작해야 의미가 있다.
        return START_NOT_STICKY
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "통화",
                // 통화 중 표시일 뿐이라 소리나 진동은 필요 없다.
                NotificationManager.IMPORTANCE_LOW,
            ).apply { setShowBadge(false) },
        )
    }

    private fun buildNotification(peer: String?): Notification {
        // 알림을 누르면 통화 화면으로 돌아온다.
        //
        // 런처가 쓰는 인텐트를 그대로 써야 한다. Intent(this, MainActivity::class)
        // 처럼 컴포넌트를 직접 지정하면, 매니페스트의 taskAffinity="" 와 맞물려
        // 기존 태스크를 되살리는 대신 **새 태스크를 만든다.** 그러면 최근 목록에
        // 앱이 둘로 보이고, 최악의 경우 인스턴스가 두 개 살아 같은 내선으로 SIP
        // 등록이 두 번 나간다.
        val launch = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pending = PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("통화 중")
            .setContentText(if (peer.isNullOrBlank()) "인터폰과 통화하고 있습니다" else peer)
            .setSmallIcon(R.drawable.ic_stat_call)
            .setContentIntent(pending)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .build()
    }
}
