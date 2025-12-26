#!/usr/bin/env python3

"""Situational awareness utility for Windows hosts.

The script mirrors the capabilities of the PowerShell situational awareness script
but is implemented in Python 3. It validates outbound connectivity for common
ports, enumerates logged-on users and cached credentials, prints core operating
system details, inventories outbound firewall allow rules, and highlights
scheduled tasks that are configured to run with elevated access.

The tool is designed for incident responders who need to perform quick triage on
Windows endpoints without installing third-party packages. When PowerShell or
other native utilities are unavailable, the script degrades gracefully and
reports which data points could not be collected.
"""


from __future__ import annotations

import argparse
import datetime as _dt
import json
import platform
import shutil
import socket
import subprocess
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Optional

DEFAULT_PORT_TARGETS = {
    22: "github.com",
    80: "example.com",
    443: "www.microsoft.com",
    3389: "rdp.microsoft.com",
}
DEFAULT_PORTS = (22, 80, 443)
DEFAULT_TEST_HOST = "8.8.8.8"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Collect situational awareness data for the local Windows system."
    )
    parser.add_argument(
        "--ports",
        nargs="*",
        type=int,
        default=list(DEFAULT_PORTS),
        help="One or more TCP ports to test for outbound connectivity.",
    )
    parser.add_argument(
        "--port-target",
        action="append",
        metavar="PORT=HOST",
        help=(
            "Override the default host used when testing a specific port. "
            "Example: --port-target 3389=contoso.com"
        ),
    )
    parser.add_argument(
        "--default-host",
        default=DEFAULT_TEST_HOST,
        help="Fallback host used for connectivity tests when a port lacks an explicit mapping.",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=5.0,
        help="Socket timeout (in seconds) for outbound connectivity tests.",
    )
    parser.add_argument(
        "--firewall-limit",
        type=int,
        default=25,
        help="Maximum number of outbound firewall rules to display in the report.",
    )
    parser.add_argument(
        "--report",
        type=Path,
        help="Optional path to write the collected data as JSON.",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Suppress console output; only useful when combined with --report.",
    )
    return parser.parse_args()


def build_port_map(args: argparse.Namespace) -> Dict[int, str]:
    port_map = dict(DEFAULT_PORT_TARGETS)
    for port in args.ports:
        port_map.setdefault(port, args.default_host)

    if args.port_target:
        for mapping in args.port_target:
            if "=" not in mapping:
                print(
                    f"[!] Ignoring malformed port mapping '{mapping}'. Expected format PORT=HOST.",
                    file=sys.stderr,
                )
                continue
            port_str, host = mapping.split("=", 1)
            try:
                port = int(port_str.strip())
            except ValueError:
                print(
                    f"[!] Ignoring port mapping with non-numeric port '{port_str}'.",
                    file=sys.stderr,
                )
                continue
            if not host.strip():
                print(
                    f"[!] Ignoring port mapping for {port} with empty host value.",
                    file=sys.stderr,
                )
                continue
            port_map[port] = host.strip()
    return port_map


def test_outbound_port(port: int, host: str, timeout: float) -> Dict[str, Optional[str]]:
    start = _dt.datetime.utcnow()
    result: Dict[str, Optional[str]] = {
        "port": port,
        "target": host,
        "reachable": False,
        "latency_ms": None,
        "error": None,
    }
    try:
        with socket.create_connection((host, port), timeout=timeout) as sock:
            sock.settimeout(timeout)
            sock.send(b"\0")
        latency = (_dt.datetime.utcnow() - start).total_seconds() * 1000
        result["reachable"] = True
        result["latency_ms"] = round(latency, 2)
    except Exception as exc:  # pylint: disable=broad-except
        result["error"] = str(exc)
    return result


def collect_outbound_tests(port_map: Dict[int, str], timeout: float) -> List[Dict[str, Optional[str]]]:
    tests = []
    for port, host in sorted(port_map.items()):
        tests.append(test_outbound_port(port, host, timeout))
    return tests


def run_command(command: Iterable[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="ignore",
    )


def collect_logged_on_users() -> Dict[str, object]:
    quser_path = shutil.which("quser") or shutil.which("query")
    if not quser_path:
        return {"available": False, "users": [], "note": "quser/query command not found."}

    proc = run_command([quser_path, "user"])
    if proc.returncode != 0:
        return {
            "available": False,
            "users": [],
            "note": f"{quser_path} returned {proc.returncode}: {proc.stderr.strip()}",
        }

    lines = [line.rstrip() for line in proc.stdout.splitlines() if line.strip()]
    if not lines:
        return {"available": True, "users": []}

    data_lines = [line for line in lines if not line.lower().startswith("username")]
    users: List[Dict[str, str]] = []
    for line in data_lines:
        parts = line.split()
        if not parts:
            continue
        username = parts[0]
        state = "" if len(parts) < 3 else parts[2]
        logon_time = ""
        if len(parts) >= 6:
            logon_time = " ".join(parts[3:6])
        users.append({"username": username, "state": state, "logon_time": logon_time})
    return {"available": True, "users": users}


def collect_cached_profiles() -> Dict[str, object]:
    powershell = shutil.which("powershell") or shutil.which("pwsh")
    if not powershell:
        return {
            "available": False,
            "profiles": [],
            "note": "PowerShell is required to enumerate cached user profiles.",
        }
    script = (
        "Get-CimInstance Win32_UserProfile | Where-Object { $_.LocalPath -and $_.LocalPath -like 'C:\\Users*' } "
        "| Select-Object LocalPath, LastUseTime, Loaded, Special"
    )
    proc = run_command([powershell, "-NoProfile", "-Command", script])
    if proc.returncode != 0:
        return {
            "available": False,
            "profiles": [],
            "note": f"PowerShell returned {proc.returncode}: {proc.stderr.strip()}",
        }

    profiles: List[Dict[str, object]] = []
    lines = [line for line in proc.stdout.splitlines() if line.strip()]
    if len(lines) <= 2:
        return {"available": True, "profiles": []}
    # Skip header lines generated by Select-Object formatting
    for line in lines[2:]:
        local_path = line[:40].strip()
        last_use_raw = line[40:65].strip()
        loaded = line[65:75].strip()
        special = line[75:].strip()
        last_use = None
        if last_use_raw:
            try:
                last_use = parse_powershell_datetime(last_use_raw)
            except ValueError:
                last_use = last_use_raw
        profiles.append(
            {
                "local_path": local_path,
                "last_use": last_use,
                "loaded": loaded.lower() == "true",
                "special": special.lower() == "true",
            }
        )
    return {"available": True, "profiles": profiles}


def parse_powershell_datetime(value: str) -> str:
    # Example input: "4/22/2024 3:04:58 PM"
    try:
        parsed = _dt.datetime.strptime(value, "%m/%d/%Y %I:%M:%S %p")
        return parsed.isoformat()
    except ValueError as exc:
        raise ValueError("Unrecognized PowerShell datetime format") from exc


def collect_last_boot_time() -> Dict[str, Optional[str]]:
    powershell = shutil.which("powershell") or shutil.which("pwsh")
    if powershell:
        cmd = [
            powershell,
            "-NoProfile",
            "-Command",
            "(Get-CimInstance Win32_OperatingSystem).LastBootUpTime",
        ]
        proc = run_command(cmd)
        if proc.returncode == 0 and proc.stdout.strip():
            return {
                "source": "PowerShell",
                "value": convert_wmi_datetime(proc.stdout.strip()),
            }
    wmic = shutil.which("wmic")
    if wmic:
        proc = run_command([wmic, "os", "get", "lastbootuptime", "/value"])
        if proc.returncode == 0 and proc.stdout:
            for line in proc.stdout.splitlines():
                if line.lower().startswith("lastbootuptime="):
                    _, value = line.split("=", 1)
                    return {
                        "source": "wmic",
                        "value": convert_wmi_datetime(value.strip()),
                    }
    return {"source": None, "value": None}


def convert_wmi_datetime(wmi_value: str) -> Optional[str]:
    # WMI timestamps look like 20240422150458.000000-420
    if not wmi_value:
        return None
    try:
        dt = _dt.datetime.strptime(wmi_value[:14], "%Y%m%d%H%M%S")
        return dt.isoformat()
    except ValueError:
        return wmi_value


def collect_system_metadata(last_boot: Dict[str, Optional[str]]) -> Dict[str, Optional[str]]:
    boot_time = last_boot.get("value")
    uptime = None
    if boot_time:
        try:
            boot_dt = _dt.datetime.fromisoformat(boot_time)
            uptime = str(_dt.datetime.utcnow() - boot_dt)
        except ValueError:
            uptime = None
    return {
        "Computer Name": platform.node(),
        "OS": f"{platform.system()} {platform.release()}",
        "Version": platform.version(),
        "Architecture": platform.machine(),
        "Processor": platform.processor(),
        "Boot Time": boot_time,
        "Uptime": uptime,
        "Python": platform.python_version(),
    }


def collect_firewall_rules(limit: int) -> Dict[str, object]:
    powershell = shutil.which("powershell") or shutil.which("pwsh")
    if not powershell:
        return {
            "available": False,
            "rules": [],
            "note": "PowerShell Get-NetFirewallRule is required to enumerate firewall rules.",
        }
    script = (
        "Get-NetFirewallRule -Direction Outbound -Action Allow | "
        f"Select-Object -First {max(1, limit)} DisplayName, Enabled, Profile, RemoteAddress, RemotePort, Program, PolicyStoreSource"
    )
    proc = run_command([powershell, "-NoProfile", "-Command", script])
    if proc.returncode != 0:
        return {
            "available": False,
            "rules": [],
            "note": f"PowerShell returned {proc.returncode}: {proc.stderr.strip()}",
        }
    lines = [line for line in proc.stdout.splitlines() if line.strip()]
    if len(lines) <= 2:
        return {"available": True, "rules": []}
    rules: List[Dict[str, str]] = []
    for line in lines[2:]:
        display = line[:35].strip()
        enabled = line[35:45].strip()
        profile = line[45:60].strip()
        remote_addr = line[60:87].strip()
        remote_port = line[87:100].strip()
        program = line[100:140].strip()
        store = line[140:].strip()
        rules.append(
            {
                "display_name": display,
                "enabled": enabled,
                "profile": profile,
                "remote_address": remote_addr,
                "remote_port": remote_port,
                "program": program,
                "policy_store": store,
            }
        )
    return {"available": True, "rules": rules}


def collect_elevated_tasks() -> Dict[str, object]:
    schtasks = shutil.which("schtasks")
    if not schtasks:
        return {
            "available": False,
            "tasks": [],
            "note": "schtasks.exe not found; cannot enumerate scheduled tasks.",
        }
    proc = run_command([schtasks, "/query", "/fo", "LIST", "/v"])
    if proc.returncode != 0:
        return {
            "available": False,
            "tasks": [],
            "note": f"schtasks returned {proc.returncode}: {proc.stderr.strip()}",
        }
    tasks: List[Dict[str, str]] = []
    current: Dict[str, str] = {}
    for line in proc.stdout.splitlines():
        stripped = line.strip()
        if not stripped:
            if current:
                if is_highest_privilege_task(current):
                    tasks.append(extract_task_summary(current))
                current = {}
            continue
        if ":" in line:
            key, value = line.split(":", 1)
            current[key.strip().lower()] = value.strip()
    if current and is_highest_privilege_task(current):
        tasks.append(extract_task_summary(current))
    return {"available": True, "tasks": tasks}


def is_highest_privilege_task(task: Dict[str, str]) -> bool:
    run_level = task.get("run level") or task.get("runlevel")
    if run_level and "highest" in run_level.lower():
        return True
    # Some systems expose "principal run level"
    principal_run_level = task.get("principal run level")
    if principal_run_level and "highest" in principal_run_level.lower():
        return True
    return False


def extract_task_summary(task: Dict[str, str]) -> Dict[str, str]:
    return {
        "name": task.get("taskname") or task.get("task name") or "<unknown>",
        "author": task.get("author", ""),
        "run_as": task.get("run as user", ""),
        "task_to_run": task.get("task to run", task.get("action", "")),
        "schedule": task.get("schedule type", ""),
        "last_run_time": task.get("last run time", ""),
    }


def format_table(rows: List[Dict[str, object]], headers: List[str]) -> str:
    if not rows:
        return "(no data)"
    col_widths = {header: len(header) for header in headers}
    for row in rows:
        for header in headers:
            value = str(row.get(header, ""))
            col_widths[header] = max(col_widths[header], len(value))

    def format_row(row_values: Iterable[str]) -> str:
        return "  ".join(
            value.ljust(col_widths[header])
            for header, value in zip(headers, row_values)
        )

    header_line = format_row(headers)
    separator = "  ".join("-" * col_widths[header] for header in headers)
    data_lines = [format_row([str(row.get(header, "")) for header in headers]) for row in rows]
    return "\n".join([header_line, separator, *data_lines])


def print_section(title: str, content: str) -> None:
    print(f"\n=== {title} ===")
    print(content)


def main() -> None:
    args = parse_args()
    port_map = build_port_map(args)

    outbound_tests = collect_outbound_tests(port_map, args.timeout)
    logged_on = collect_logged_on_users()
    cached_profiles = collect_cached_profiles()
    last_boot = collect_last_boot_time()
    system_metadata = collect_system_metadata(last_boot)
    firewall_rules = collect_firewall_rules(args.firewall_limit)
    elevated_tasks = collect_elevated_tasks()

    report = {
        "generated_at": _dt.datetime.utcnow().isoformat() + "Z",
        "parameters": {
            "ports": sorted(set(port_map.keys())),
            "default_host": args.default_host,
            "timeout": args.timeout,
            "firewall_limit": args.firewall_limit,
        },
        "outbound_tests": outbound_tests,
        "logged_on_users": logged_on,
        "cached_profiles": cached_profiles,
        "last_boot": last_boot,
        "system_metadata": system_metadata,
        "firewall_rules": firewall_rules,
        "elevated_tasks": elevated_tasks,
    }

    if not args.quiet:
        system_rows = [
            {"Field": key, "Value": value if value is not None else ""}
            for key, value in system_metadata.items()
        ]
        print_section(
            "System Metadata",
            format_table(system_rows, ["Field", "Value"]),
        )

        test_rows = [
            {
                "Port": item["port"],
                "Target": item["target"],
                "Reachable": "Yes" if item["reachable"] else "No",
                "Latency (ms)": item["latency_ms"] if item["latency_ms"] is not None else "",
                "Error": item["error"] or "",
            }
            for item in outbound_tests
        ]
        print_section(
            "Outbound Connectivity",
            format_table(test_rows, ["Port", "Target", "Reachable", "Latency (ms)", "Error"]),
        )

        if logged_on.get("available"):
            user_rows = [
                {
                    "Username": user.get("username", ""),
                    "State": user.get("state", ""),
                    "Logon Time": user.get("logon_time", ""),
                }
                for user in logged_on.get("users", [])
            ]
            content = (
                format_table(user_rows, ["Username", "State", "Logon Time"])
                if user_rows
                else "(no active sessions)"
            )
        else:
            content = logged_on.get("note", "Unable to enumerate logged-on users.")
        print_section("Logged-On Users", content)

        if cached_profiles.get("available"):
            profile_rows = [
                {
                    "Profile": profile.get("local_path", ""),
                    "Last Used": profile.get("last_use", ""),
                    "Loaded": "Yes" if profile.get("loaded") else "No",
                    "Special": "Yes" if profile.get("special") else "No",
                }
                for profile in cached_profiles.get("profiles", [])
            ]
            content = (
                format_table(profile_rows, ["Profile", "Last Used", "Loaded", "Special"])
                if profile_rows
                else "(no cached profiles detected)"
            )
        else:
            content = cached_profiles.get("note", "Unable to enumerate cached profiles.")
        print_section("Cached User Profiles", content)

        if firewall_rules.get("available"):
            rule_rows = [
                {
                    "Display Name": rule.get("display_name", ""),
                    "Enabled": rule.get("enabled", ""),
                    "Profile": rule.get("profile", ""),
                    "Remote Address": rule.get("remote_address", ""),
                    "Remote Port": rule.get("remote_port", ""),
                    "Program": rule.get("program", ""),
                }
                for rule in firewall_rules.get("rules", [])
            ]
            content = (
                format_table(
                    rule_rows,
                    [
                        "Display Name",
                        "Enabled",
                        "Profile",
                        "Remote Address",
                        "Remote Port",
                        "Program",
                    ],
                )
                if rule_rows
                else "(no outbound allow rules returned)"
            )
        else:
            content = firewall_rules.get("note", "Unable to enumerate firewall rules.")
        print_section("Outbound Firewall Rules", content)

        if elevated_tasks.get("available"):
            task_rows = [
                {
                    "Task Name": task.get("name", ""),
                    "Run As": task.get("run_as", ""),
                    "Author": task.get("author", ""),
                    "Schedule": task.get("schedule", ""),
                    "Last Run": task.get("last_run_time", ""),
                    "Action": task.get("task_to_run", ""),
                }
                for task in elevated_tasks.get("tasks", [])
            ]
            content = (
                format_table(
                    task_rows,
                    ["Task Name", "Run As", "Author", "Schedule", "Last Run", "Action"],
                )
                if task_rows
                else "(no elevated tasks detected)"
            )
        else:
            content = elevated_tasks.get("note", "Unable to enumerate scheduled tasks.")
        print_section("Elevated Scheduled Tasks", content)

    if args.report:
        try:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, indent=2))
            if not args.quiet:
                print(f"\nReport written to {args.report}")
        except OSError as exc:
            print(f"[!] Failed to write report to {args.report}: {exc}", file=sys.stderr)


if __name__ == "__main__":
    main() 
