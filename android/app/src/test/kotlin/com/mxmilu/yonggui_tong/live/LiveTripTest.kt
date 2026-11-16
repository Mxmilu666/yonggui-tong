package com.mxmilu.yonggui_tong.live

import android.app.Notification
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34, 36])
class LiveTripTest {
    private val start = 1_730_000_000_000L
    private val context get() = RuntimeEnvironment.getApplication()

    private fun stage(at: Long, chip: String, target: Long?, station: String = "鼓楼", countdownInChip: Boolean = true) = JSONObject()
        .put("at", at).put("title", "倒计时测试").put("text", chip).put("chip", chip)
        .put("stationName", station).put("countdownInChip", countdownInChip)
        .put("countdownTo", target ?: JSONObject.NULL)

    private fun trip(focus: Boolean, end: Long, vararg stages: JSONObject) = LiveTrip.Trip(context,
        JSONObject().put("endsAt", end).put("open", "/arrivals/16")
            .put("stages", JSONArray(stages.toList())), focus)

    private fun focusParam(frame: LiveTrip.Frame) = JSONObject(frame.notification.extras.getString("miui.focus.param")!!)
        .getJSONObject("param_v2")

    private fun digits(frame: LiveTrip.Frame) = focusParam(frame).getJSONObject("param_island")
        .getJSONObject("bigIslandArea").getJSONObject("sameWidthDigitInfo")

    @Test
    fun countdownKeepsTickingWithOrWithoutFocusPermission() {
        val target = start + 135_050
        for (focus in listOf(false, true)) {
            val trip = trip(focus, target + 5_000, stage(start, "等车", target))
            val first = trip.frame(start, null)!!
            assertEquals("02:16", first.notification.extras.getString("android.shortCriticalText"))
            assertEquals(start + 50, first.nextAt)
            assertEquals(target, first.notification.`when`)
            assertTrue(first.notification.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
            if (focus) {
                assertEquals("02:16", digits(first).getString("digit"))
                assertEquals(135_050L, digits(first).getJSONObject("timerInfo").getLong("timerTotal"))
                assertTrue(focusParam(first).getBoolean("enableFloat"))
            }

            // The service renders just after this deadline; focus access must not skip these ticks.
            val tickAt = first.nextAt + 20
            val tick = trip.frame(tickAt, first.stageAt)!!
            assertEquals("02:15", tick.notification.extras.getString("android.shortCriticalText"))
            assertEquals(start + 1_050, tick.nextAt)
            assertEquals(target, tick.notification.`when`)
            if (focus) {
                assertEquals("02:15", digits(tick).getString("digit"))
                val timer = digits(tick).getJSONObject("timerInfo")
                assertEquals(-1, timer.getInt("timerType"))
                assertEquals(target, timer.getLong("timerWhen"))
                assertEquals(135_050L, timer.getLong("timerTotal"))
                assertEquals(tickAt, timer.getLong("timerSystemCurrent"))
                assertFalse(focusParam(tick).getBoolean("enableFloat"))
            } else {
                assertFalse(tick.notification.extras.containsKey("miui.focus.param"))
            }
        }
    }

    @Test
    fun arrivalShowsDwellStatusUntilDepartureInsteadOfAnotherCountdown() {
        val arrival = start + 2_500
        val departure = arrival + 3_000
        for (focus in listOf(false, true)) {
            val trip = trip(focus, departure, stage(start, "等车", arrival),
                stage(arrival, "停靠中", departure, countdownInChip = false))
            val waiting = trip.frame(start, null)!!
            val dwelling = trip.frame(arrival, waiting.stageAt)!!
            assertEquals("停靠中", dwelling.notification.extras.getString("android.shortCriticalText"))
            assertEquals("停靠中", dwelling.notification.extras.getString(Notification.EXTRA_TEXT))
            assertEquals(departure, dwelling.notification.`when`)
            assertTrue(dwelling.notification.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
            if (focus) {
                val big = focusParam(dwelling).getJSONObject("param_island").getJSONObject("bigIslandArea")
                assertEquals("鼓楼", big.getJSONObject("imageTextInfoLeft").getJSONObject("textInfo").getString("title"))
                assertEquals("停靠中", big.getJSONObject("textInfo").getString("title"))
                assertFalse(big.has("sameWidthDigitInfo"))
            }
            val stillDwelling = trip.frame(departure - 1, dwelling.stageAt)!!
            assertEquals("停靠中", stillDwelling.notification.extras.getString("android.shortCriticalText"))
            assertEquals(departure, stillDwelling.nextAt)
            assertNull(trip.frame(departure, stillDwelling.stageAt))
        }
    }

    @Test
    fun leftStationChangesAtTransferWithoutParsingNotificationTitle() {
        val transfer = start + 2_500
        val arrival = transfer + 3_000
        val trip = trip(true, arrival + 1_000,
            stage(start, "换乘", transfer, station = "鼓楼"),
            stage(transfer, "到站", arrival, station = "东门口（天一广场）"))
        val first = trip.frame(start, null)!!
        var big = focusParam(first).getJSONObject("param_island").getJSONObject("bigIslandArea")
        assertEquals("鼓楼", big.getJSONObject("imageTextInfoLeft").getJSONObject("textInfo").getString("title"))
        val next = trip.frame(transfer, first.stageAt)!!
        big = focusParam(next).getJSONObject("param_island").getJSONObject("bigIslandArea")
        assertEquals("东门口（天一广场）", big.getJSONObject("imageTextInfoLeft").getJSONObject("textInfo").getString("title"))
        assertEquals(arrival, digits(next).getJSONObject("timerInfo").getLong("timerWhen"))
        assertFalse(big.has("textInfo"))
    }

    @Test
    fun finalTimerIsClearedAtItsTargetWithoutWaitingForAnotherStage() {
        val target = start + 2_500
        val end = target + 5_000
        val trip = trip(true, end, stage(start, "即将到站", target))
        val first = trip.frame(start, null)!!
        val elapsed = trip.frame(target, first.stageAt)!!
        assertEquals("即将到站", elapsed.notification.extras.getString("android.shortCriticalText"))
        assertFalse(elapsed.notification.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
        assertFalse(focusParam(elapsed).getJSONObject("param_island")
            .getJSONObject("bigIslandArea").has("sameWidthDigitInfo"))
        assertFalse(focusParam(elapsed).getBoolean("enableFloat"))
        assertEquals(end, elapsed.nextAt)
        assertNull(trip.frame(end, elapsed.stageAt))
    }
}
