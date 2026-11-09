package dev.tuist.app.navigation

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.*
import org.junit.Test

class AppRouteTest {
    private val production = "https://tuist.dev"
    private val detail = "tuist://app/acme/mobile/previews/opaque-id"

    @Test
    fun `public canonical roots have no query`() {
        assertEquals("tuist://app/previews", AppRoute.Previews.toUrl())
        assertEquals("tuist://app/profile", AppRoute.Profile.toUrl())
        assertEquals(AppRoute.Previews, AppRoute.parse(AppRoute.Previews.toUrl(), "https://other.dev/base"))
        assertEquals(AppRoute.Profile, AppRoute.parse(AppRoute.Profile.toUrl(), production))
    }

    @Test
    fun `canonical details encode segments and roundtrip opaque identifiers`() {
        val route = AppRoute.PreviewDetail("équipe", "mobile+?", "id:#%&=🍎", "https://self.example/base")
        val url = route.toUrl()
        assertEquals(
            "https://self.example/base/%C3%A9quipe/mobile%2B%3F/previews/id%3A%23%25%26%3D%F0%9F%8D%8E",
            url,
        )
        assertEquals(route, AppRoute.parse(url, route.server))
        assertEquals(
            "tuist://app/%C3%A9quipe/mobile%2B%3F/previews/id%3A%23%25%26%3D%F0%9F%8D%8E?server=https%3A%2F%2Fself.example%2Fbase",
            route.toHandoffUrl(),
        )
        assertEquals(route, AppRoute.parse(route.toHandoffUrl(), route.server))
    }

    @Test
    fun `omitted server means production only not the current environment`() {
        assertEquals(AppRoute.PreviewDetail("acme", "mobile", "opaque-id"), AppRoute.parse(detail, production))
        assertNull(AppRoute.parse(detail, "https://staging.tuist.dev"))
        assertNull(AppRoute.parse(detail, "$production/base"))
    }

    @Test
    fun `canonical server equality includes scheme effective port and full base path`() {
        val route = AppRoute.PreviewDetail("a", "p", "id", "https://SELF.example:443/base/")
        val url = route.toUrl()
        assertEquals("https://self.example/base/a/p/previews/id", url)
        assertEquals("tuist://app/a/p/previews/id?server=https%3A%2F%2Fself.example%2Fbase", route.toHandoffUrl())
        assertEquals(AppRoute.PreviewDetail("a", "p", "id", "https://self.example/base"), AppRoute.parse(url, "https://self.example/base"))
        listOf("http://self.example/base", "https://self.example:444/base", "https://self.example", "https://self.example/Base", "https://self.example/base/child", "https://other.example/base").forEach {
            assertNull(it, AppRoute.parse(url, it))
        }
    }

    @Test
    fun `legacy https matches current server base including default port and trailing base slash`() {
        val expected = AppRoute.PreviewDetail("a", "p", "not-a-uuid", "https://self.example/base")
        assertEquals(expected, AppRoute.parse("https://SELF.example:443/base/a/p/previews/not-a-uuid", "https://self.example/base/"))
        assertEquals(expected, AppRoute.parse("https://self.example/base/a/p/previews/not-a-uuid", "https://self.example:443/base"))
        listOf(
            "https://self.example/a/p/previews/not-a-uuid",
            "https://self.example/base2/a/p/previews/not-a-uuid",
            "https://other.example/base/a/p/previews/not-a-uuid",
            "https://self.example:444/base/a/p/previews/not-a-uuid",
            "http://self.example/base/a/p/previews/not-a-uuid",
            "https://self.example/base/a/p/previews/not-a-uuid?x=1",
            "https://self.example/base/a/p/previews/not-a-uuid#fragment",
        ).forEach { assertNull(it, AppRoute.parse(it, "https://self.example/base/")) }
    }

    @Test
    fun `reject malformed components authorities paths and queries`() {
        val invalid = listOf(
            "tuist://app/previews/", "tuist://app/profile/extra", "tuist://app//profile",
            "tuist://app/profile?", "tuist://app/previews?server=https%3A%2F%2Ftuist.dev",
            "tuist://user@app/previews", "tuist://app:443/previews", "tuist://app/previews#",
            "tuist://wrong/previews", "tuist:app/previews", "tuist://app", "$detail/", "$detail/extra",
            "$detail?unknown=value", "$detail?server=", "$detail?server=https%3A%2F%2Ftuist.dev&server=https%3A%2F%2Ftuist.dev",
            "$detail?server=https%3A%2F%2Ftuist.dev&unknown", "$detail?server=https%3A%2F%2Ftuist.dev&",
            "$detail?server=https%3A%2F%2Fuser%40tuist.dev", "$detail?server=https%3A%2F%2Ftuist.dev%23fragment",
        )
        invalid.forEach { assertNull(it, AppRoute.parse(it, production)) }
        listOf("", ".", "..", "%2e", "%2E%2e", "a%2Fb", "a%5Cb", "%20", "a%09b", "%00", "%C2%A0", "%FF", "%C0%AF", "%", "%ZZ").forEach { component ->
            listOf(
                "tuist://app/$component/p/previews/id",
                "tuist://app/a/$component/previews/id",
                "tuist://app/a/p/previews/$component",
                "https://tuist.dev/a/p/previews/$component",
            ).forEach { assertNull(it, AppRoute.parse(it, production)) }
        }
    }

    @Test
    fun `generator rejects invalid segments rather than emitting ambiguous routes`() {
        listOf("", ".", "..", "a/b", "a\\b", "a b", "a\nb", "latest").forEach { id ->
            assertTrue(id, runCatching { AppRoute.PreviewDetail("a", "p", id).toUrl() }.isFailure)
            assertTrue(id, runCatching { AppRoute.PreviewDetail("a", "p", id).toHandoffUrl() }.isFailure)
        }
    }

    @Test
    fun `shared fixtures define exact canonical and explicit handoff spellings`() {
        val fixture = Json.parseToJsonElement(
            checkNotNull(javaClass.classLoader!!.getResourceAsStream("routes.json")).bufferedReader().use { it.readText() },
        ).jsonObject
        fixture.getValue("previews").jsonArray.forEach { element ->
            val item = element.jsonObject.mapValues { it.value.jsonPrimitive.content }
            val route = AppRoute.PreviewDetail(item.getValue("account"), item.getValue("project"), item.getValue("id"), item.getValue("server"))
            assertEquals(item.getValue("canonical"), route.toUrl())
            assertEquals(item.getValue("handoff"), route.toHandoffUrl())
            val canonical = AppRoute.parse(route.toUrl(), route.server)
            assertNotNull(canonical)
            assertEquals(canonical, AppRoute.parse(route.toHandoffUrl(), route.server))
            assertEquals(route.toUrl(), canonical!!.toUrl())
            assertNull(AppRoute.parse(route.toHandoffUrl(), "https://wrong.example"))
        }
        fixture.getValue("web_only").jsonArray.forEach { element ->
            val url = element.jsonPrimitive.content
            assertNull(url, AppRoute.parse(url, production))
            assertTrue(url, AppRoute.isCurrentServerWebUrl(url, production))
        }
    }

    @Test
    fun `browser fallback is same server only and never accepts custom or malformed URLs`() {
        listOf(
            "tuist://app/a/p/previews/id/extra", "tuist://app/profile/extra",
            "https://wrong.dev/a/p/previews/id/download", "http://tuist.dev/a/p/previews/id/download",
            "https://tuist.dev:444/a/p/previews/id/download", "https://user@tuist.dev/a/p/previews/id/download",
            "https://tuist.dev/a/../previews/id/download", "https://tuist.dev/a/p/previews/%FF",
        ).forEach { assertFalse(it, AppRoute.isCurrentServerWebUrl(it, production)) }
        assertTrue(AppRoute.isCurrentServerWebUrl("https://SELF.example:443/base/a/p/previews/latest?branch=main#build", "https://self.example/base/"))
        assertFalse(AppRoute.isCurrentServerWebUrl("https://self.example/base2/a/p/previews/latest", "https://self.example/base"))
        assertNull(AppRoute.parse("tuist://app/a/p/previews/latest", production))
        assertNull(AppRoute.parse("https://tuist.dev/a/p/previews/%6Catest", production))
    }

    @Test
    fun `http development links require the configured origin and server trailing slashes normalize`() {
        val route = AppRoute.PreviewDetail("a", "p", "id", "http://localhost:8080/base")
        assertEquals(route, AppRoute.parse("http://localhost:8080/base/a/p/previews/id", "http://localhost:8080/base///"))
        assertEquals(route, AppRoute.parse(route.toUrl(), "http://localhost:8080/base///"))
        assertEquals(AppRoute.PreviewDetail("a", "p", "id", "http://localhost"), AppRoute.parse("http://localhost:80/a/p/previews/id", "http://localhost///"))
        assertNull(AppRoute.parse("http://localhost:8080/base/a/p/previews/id", "https://localhost:8080/base"))
        assertNull(AppRoute.parse("http://localhost:0/a/p/previews/id", "http://localhost:0"))
        assertNull(AppRoute.parse("tuist://app/a/p/previews/id?server=http%3A%2F%2Flocalhost%3A0", "http://localhost:0"))
    }
}
