"""Tests for the rack switch fleet renderer and differ.

The interesting fixture is a real `show running-config` transcript taken off
ber1-tor-b, pager artefacts and all. Its NUL bytes are written as the two
characters \\0 so the fixture stays reviewable in a diff, and are decoded on the
way in.

    python3 -m unittest discover -s infra/rack-switch-fleet/tests
"""

import json
import os
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import config_text as ct
import models
import render


def live_transcript():
    text = (ROOT / "tests" / "fixtures" / "ber1-tor-b-running-config.txt").read_text()
    return text.replace("\\0", "\x00")


def ber1():
    return json.loads((ROOT / "sites" / "ber1.json").read_text())


class TerminalNoise(unittest.TestCase):
    def test_carriage_return_erase_leaves_only_the_last_write(self):
        line = "Press any key to continue (Q to quit)\r" + " " * 76 + "\r#"
        self.assertEqual(ct.apply_carriage_returns(line).strip(), "#")

    def test_nul_after_carriage_return_does_not_survive_normalising(self):
        # The firmware sends a bare CR as CR NUL, and str.strip() does not touch NUL,
        # so an unscrubbed pager line reads as a config command that is not there.
        self.assertEqual(ct.normalize("Press any key to continue (Q to quit)\x00    #"), [])

    def test_pager_prompt_does_not_swallow_the_line_it_erases(self):
        line = "Press any key to continue (Q to quit)\x00      no controller cloud-based"
        self.assertEqual(ct.normalize(line), ["no controller cloud-based"])

    def test_separators_and_banner_are_not_configuration(self):
        self.assertEqual(ct.normalize("!SX3832\n#\n\nend\n"), [])


class Transcripts(unittest.TestCase):
    def test_strip_transcript_drops_the_echo_and_the_next_prompt(self):
        body = ct.strip_transcript(live_transcript(), "show running-config")
        self.assertTrue(body.lstrip().startswith("!SX3832"))
        self.assertNotIn("show running-config", body)
        self.assertNotIn("ber1-tor-b#", body.split("\n")[-1])

    def test_a_command_that_never_ran_is_an_error_not_an_empty_config(self):
        with self.assertRaises(ValueError):
            ct.strip_transcript(live_transcript(), "show startup-config")


class Rendering(unittest.TestCase):
    def test_rendered_config_matches_the_live_switch(self):
        site = ber1()
        device = render.device_by_name(site, "ber1-tor-b")
        body = ct.strip_transcript(live_transcript(), "show running-config")
        self.assertEqual(
            ct.diff(render.render(site, device), body, "rendered", "live"), [],
            "the render no longer reproduces the switch it was derived from",
        )

    def test_the_admin_secret_is_never_rendered(self):
        site = ber1()
        for device in site["devices"]:
            self.assertNotIn("user name", render.render(site, device))

    def test_devices_differ_only_where_the_site_says_they_do(self):
        site = ber1()
        a = render.render(site, render.device_by_name(site, "ber1-tor-a")).split("\n")
        b = render.render(site, render.device_by_name(site, "ber1-tor-b")).split("\n")
        differing = [x for x, y in zip(a, b) if x != y]
        self.assertEqual(differing, ['hostname "ber1-tor-a"',
                                     "  ip address 192.168.0.11 255.255.255.0"])

    def test_the_committed_configs_are_what_the_site_definition_renders(self):
        site = ber1()
        for device in site["devices"]:
            path = ROOT / "configs" / site["site"] / f"{device['name']}.cfg"
            self.assertEqual(path.read_text(), render.render(site, device),
                             f"{path.name} is stale; run `mise run rack:fleet render`")

    def test_a_model_the_renderer_has_never_seen_is_refused(self):
        with self.assertRaises(KeyError):
            models.ports("catalyst-9300")


class ApplyOrdering(unittest.TestCase):
    def test_the_switch_with_the_smallest_blast_radius_goes_first(self):
        order = [d["name"] for d in render.apply_order(ber1())]
        self.assertEqual(order, ["ber1-tor-b", "ber1-tor-a", "ber1-mgmt"])

    def test_every_device_says_why_it_sits_where_it_does(self):
        for device in ber1()["devices"]:
            self.assertGreater(len(device["apply_note"]), 40, device["name"])

    def test_the_order_is_total_so_two_switches_are_never_applied_together(self):
        orders = [d["apply_order"] for d in ber1()["devices"]]
        self.assertEqual(len(orders), len(set(orders)))


class Planning(unittest.TestCase):
    def test_a_missing_command_is_planned_into_its_own_context(self):
        desired = "#\ninterface vlan 1\n  ip address 10.0.0.2 255.255.255.0\n  ipv6 enable\nend\n"
        actual = "#\ninterface vlan 1\n  ip address 10.0.0.2 255.255.255.0\nend\n"
        additions, removals = ct.plan(desired, actual)
        self.assertEqual(additions, [("interface vlan 1", ["ipv6 enable"])])
        self.assertEqual(removals, [])
        self.assertEqual(ct.plan_commands(additions),
                         ["configure", "interface vlan 1", "ipv6 enable", "exit", "end"])

    def test_an_unexpected_command_is_reported_rather_than_negated(self):
        desired = "interface vlan 1\n  ipv6 enable\nend\n"
        actual = "interface vlan 1\n  ipv6 enable\n  ip address 10.0.0.9 255.255.255.0\nend\n"
        additions, removals = ct.plan(desired, actual)
        self.assertEqual(additions, [])
        self.assertEqual(removals, [("interface vlan 1", "ip address 10.0.0.9 255.255.255.0")])

    def test_applying_a_config_the_switch_already_has_plans_nothing(self):
        site = ber1()
        device = render.device_by_name(site, "ber1-tor-b")
        body = ct.strip_transcript(live_transcript(), "show running-config")
        additions, _ = ct.plan(render.render(site, device), body)
        self.assertEqual(additions, [])


class Unmanaged(unittest.TestCase):
    def test_the_local_login_is_not_drift(self):
        self.assertEqual(ct.normalize("user name tuist privilege admin secret 5 $1$abc"), [])

    def test_ntp_is_not_drift_while_its_operand_order_is_unconfirmed(self):
        self.assertEqual(ct.normalize("system-time ntp UTC a.example b.example 12 c.example"), [])

    def test_backups_carry_the_config_but_not_the_secret(self):
        redacted = ct.redact(ct.strip_transcript(live_transcript(), "show running-config"))
        self.assertIn("user name tuist privilege admin secret 5 <redacted", redacted)
        self.assertNotIn("$1$EXAMPLEHASHNOTREAL", redacted)
        self.assertIn('hostname "ber1-tor-b"', redacted)

    def test_the_committed_backup_holds_no_secret(self):
        path = ROOT / "backups" / "ber1" / "ber1-tor-b.cfg"
        self.assertNotIn("$1$", path.read_text())


if __name__ == "__main__":
    unittest.main()


class ApplyGuards(unittest.TestCase):
    """The refusals that make the apply order a precondition, not a runbook line."""

    def _args(self, device):
        import argparse
        return argparse.Namespace(site="ber1", device=device, verbose=False,
                                  dry_run=True, yes=True, skip_order_check=False)

    def test_a_switch_is_refused_while_an_earlier_one_has_not_been_applied(self):
        import fleet
        original = fleet.device_diff
        fleet.device_diff = lambda site, device, verbose: (["-drifted"], "")
        try:
            with self.assertRaises(SystemExit) as raised:
                fleet.cmd_apply(self._args("ber1-tor-a"))
        finally:
            fleet.device_diff = original
        self.assertIn("ber1-tor-b", str(raised.exception))

    def test_the_first_switch_in_the_order_has_nothing_blocking_it(self):
        import fleet
        site = ber1()
        original = fleet.device_diff
        fleet.device_diff = lambda site, device, verbose: (["-drifted"], "")
        try:
            blocker = fleet.preceding_devices_clean(
                site, render.device_by_name(site, "ber1-tor-b"), False)
        finally:
            fleet.device_diff = original
        self.assertIsNone(blocker)

    def test_a_model_whose_ports_were_never_confirmed_is_never_applied(self):
        import fleet
        with self.assertRaises(SystemExit) as raised:
            fleet.cmd_apply(self._args("ber1-mgmt"))
        self.assertIn("never been read off a live unit", str(raised.exception))


class WiringRecord(unittest.TestCase):
    def test_a_port_the_model_does_not_have_is_rejected(self):
        site = ber1()
        device = dict(render.device_by_name(site, "ber1-tor-b"))
        device["ports"] = {"48": {"purpose": "uplink"}}
        with self.assertRaises(ValueError):
            render.render(site, device)

    def test_every_declared_port_exists_on_its_switch(self):
        site = ber1()
        for device in site["devices"]:
            render.check_ports(device)

    def test_the_isl_is_declared_on_both_ends(self):
        site = ber1()
        ends = {d["name"]: [p for p in d.get("ports", {}).values() if p["purpose"] == "isl"]
                for d in site["devices"] if d["role"] == "tor"}
        self.assertEqual(sorted(ends), ["ber1-tor-a", "ber1-tor-b"])
        for name, ports in ends.items():
            self.assertEqual(len(ports), 1, name)
        self.assertEqual(ends["ber1-tor-a"][0]["peer"], "ber1-tor-b")
        self.assertEqual(ends["ber1-tor-b"][0]["peer"], "ber1-tor-a")
