#!/usr/bin/python3
"""Voyage Launcher: a small Tk window for driving the simulator build.

Pick a simulator, a home airport, the window's hour, the flight timing, and
the QA toggles, then build, launch, screenshot, or record the App Store
preview without retyping `xcrun simctl launch ... -VoyageX ...` by hand.

    /usr/bin/python3 scripts/voyage_launcher.py   # the macOS Python; Homebrew and PlatformIO builds may lack Tk

Only the standard library. Layout follows the grouped-LabelFrame, grid-laid
ttk style of CPython's own Tk dialogs (Lib/idlelib/configdialog.py); there is
no comparable open-source simulator launcher to borrow from more directly.
Every launch argument here is one the app already reads; see
`SettingsStore.swift` (home airport, onboarding), `FlightSession.swift`
(short/demo flights) and `InFlightView.swift` (scene hour).
"""
import json
import os
import queue
import re
import subprocess
import sys
import threading
import tkinter as tk
from datetime import datetime
from pathlib import Path
from tkinter import ttk

ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = "com.patrickliu.voyage"
SCHEME = "Voyage"
PROJECT = ROOT / "Voyage.xcodeproj"
DERIVED = ROOT / "build" / "DerivedData-launcher"
QA_DIR = ROOT / "QA"
AIRPORTS = ["BOS", "JFK", "MIA", "RDU", "SFO", "LAX", "SEA", "YYZ", "YVR", "YQR"]

MUTE_ARGS = [
    "-soundEffectsEnabled", "<false/>",
    "-ambienceEnabled", "<false/>",
    "-announcementsEnabled", "<false/>",
]


def simulators():
    """(name, udid, state) for every available iPhone simulator."""
    out = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "-j"],
                         capture_output=True, text=True, check=True).stdout
    found = []
    for runtime, devices in json.loads(out)["devices"].items():
        if "iOS" not in runtime:
            continue
        for d in devices:
            if d["name"].startswith("iPhone"):
                found.append((d["name"], d["udid"], d["state"]))
    found.sort(key=lambda d: (d[2] != "Booted", d[0]))
    return found


class Launcher(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Voyage Launcher")
        self.resizable(True, True)
        self.log_queue = queue.Queue()
        self.busy = False
        self.devices = simulators()
        self._build()
        self.after(100, self._drain_log)

    # MARK: Layout

    def _build(self):
        pad = {"padx": 8, "pady": 4}
        body = ttk.Frame(self, padding=10)
        body.grid(sticky="nsew")
        self.columnconfigure(0, weight=1)
        self.rowconfigure(0, weight=1)
        body.columnconfigure(1, weight=1)

        # Simulator
        sim = ttk.LabelFrame(body, text="Simulator", padding=8)
        sim.grid(row=0, column=0, columnspan=2, sticky="ew", **pad)
        sim.columnconfigure(1, weight=1)
        ttk.Label(sim, text="Device").grid(row=0, column=0, sticky="w")
        names = [f"{n}  ({s.lower()})" for n, _, s in self.devices] or ["no iPhone simulators found"]
        self.device = tk.StringVar(value=names[0])
        ttk.Combobox(sim, textvariable=self.device, values=names, state="readonly").grid(
            row=0, column=1, sticky="ew", padx=(8, 0))

        # Flight
        flight = ttk.LabelFrame(body, text="Flight", padding=8)
        flight.grid(row=1, column=0, sticky="nsew", **pad)
        ttk.Label(flight, text="Home airport").grid(row=0, column=0, sticky="w")
        self.airport = tk.StringVar(value="SFO")
        ttk.Combobox(flight, textvariable=self.airport, values=AIRPORTS, state="readonly",
                     width=6).grid(row=0, column=1, sticky="w", padx=(8, 0))

        ttk.Label(flight, text="Timing").grid(row=1, column=0, sticky="w", pady=(8, 0))
        self.timing = tk.StringVar(value="short")
        for i, (label, value) in enumerate([("Real block times", "real"),
                                            ("Short takeoff and climb", "short"),
                                            ("One-minute demo flight", "demo")]):
            ttk.Radiobutton(flight, text=label, value=value, variable=self.timing).grid(
                row=2 + i, column=0, columnspan=2, sticky="w")

        # Window
        window = ttk.LabelFrame(body, text="Window", padding=8)
        window.grid(row=1, column=1, sticky="nsew", **pad)
        self.pin_hour = tk.BooleanVar(value=False)
        ttk.Checkbutton(window, text="Pin the hour", variable=self.pin_hour).grid(
            row=0, column=0, sticky="w")
        self.hour = tk.StringVar(value="10")
        ttk.Spinbox(window, from_=0, to=23, textvariable=self.hour, width=4).grid(
            row=0, column=1, sticky="w", padx=(8, 0))
        ttk.Label(window, text="0–23 at the origin; 19–5 is night").grid(
            row=1, column=0, columnspan=2, sticky="w")
        self.real_world = tk.BooleanVar(value=False)
        ttk.Checkbutton(window, text="Real-world scenery", variable=self.real_world).grid(
            row=2, column=0, columnspan=2, sticky="w", pady=(8, 0))

        # QA toggles
        qa = ttk.LabelFrame(body, text="QA", padding=8)
        qa.grid(row=2, column=0, columnspan=2, sticky="ew", **pad)
        self.mute = tk.BooleanVar(value=True)
        self.reset_onboarding = tk.BooleanVar(value=False)
        self.debug_stamp = tk.BooleanVar(value=False)
        self.recorder_demo = tk.BooleanVar(value=False)
        for i, (label, var) in enumerate([
            ("Mute sound, ambience and announcements", self.mute),
            ("Reset onboarding (show the first-run pages)", self.reset_onboarding),
            ("Jump to the passport stamp (debug builds)", self.debug_stamp),
            ("Seeded logbook for the flight recorder", self.recorder_demo),
        ]):
            ttk.Checkbutton(qa, text=label, variable=var).grid(row=i // 2, column=i % 2, sticky="w", padx=(0, 16))

        # Actions
        actions = ttk.Frame(body)
        actions.grid(row=3, column=0, columnspan=2, sticky="ew", **pad)
        self.buttons = []
        for i, (label, fn) in enumerate([
            ("Build & install", self.build_and_install),
            ("Launch", self.launch),
            ("Screenshot", self.screenshot),
            ("Record preview", self.record_preview),
            ("Open QA folder", self.open_qa),
        ]):
            b = ttk.Button(actions, text=label, command=fn)
            b.grid(row=0, column=i, padx=(0, 6))
            self.buttons.append(b)

        ttk.Label(body, text="Launch arguments").grid(row=4, column=0, columnspan=2, sticky="w", padx=8)
        self.args_preview = tk.StringVar()
        ttk.Entry(body, textvariable=self.args_preview, state="readonly").grid(
            row=5, column=0, columnspan=2, sticky="ew", padx=8)
        for var in (self.airport, self.timing, self.pin_hour, self.hour, self.real_world,
                    self.mute, self.reset_onboarding, self.debug_stamp, self.recorder_demo):
            var.trace_add("write", lambda *_: self._refresh_args())
        self._refresh_args()

        self.log = tk.Text(body, height=14, wrap="word", state="disabled",
                           font=("Menlo", 11), relief="flat", background="#111318", foreground="#d7dbe2")
        self.log.grid(row=6, column=0, columnspan=2, sticky="nsew", padx=8, pady=(8, 0))
        body.rowconfigure(6, weight=1)

    # MARK: Arguments

    def launch_args(self):
        args = ["-VoyageHomeAirport", self.airport.get()]
        if self.timing.get() == "short":
            args.append("-VoyageShortFlights")
        elif self.timing.get() == "demo":
            args.append("-VoyageDemoFlight")
        if self.pin_hour.get():
            try:
                hour = int(self.hour.get())
            except ValueError:
                hour = -1
            if not 0 <= hour <= 23:
                raise ValueError("hour must be 0-23")
            args += ["-VoyageSceneHour", str(hour)]
        if self.real_world.get():
            args.append("-VoyageRealWorldTwinEnabled")
        if self.mute.get():
            args += MUTE_ARGS
        if self.reset_onboarding.get():
            args.append("-VoyageResetOnboarding")
        if self.debug_stamp.get():
            args.append("-VoyageDebugStamp")
        if self.recorder_demo.get():
            args.append("-VoyageRecorderDemo")
        return args

    def _refresh_args(self):
        try:
            self.args_preview.set(" ".join(self.launch_args()))
        except ValueError as error:
            self.args_preview.set(f"✗ {error}")

    def udid(self):
        index = [f"{n}  ({s.lower()})" for n, _, s in self.devices].index(self.device.get())
        return self.devices[index][1]

    # MARK: Actions

    def build_and_install(self):
        def work():
            self._run(["xcodebuild", "-project", str(PROJECT), "-scheme", SCHEME,
                       "-destination", f"platform=iOS Simulator,id={self.udid()}",
                       "-derivedDataPath", str(DERIVED), "build"], quiet=True)
            app = next(DERIVED.glob("Build/Products/Debug-iphonesimulator/Voyage.app"), None)
            if app is None:
                raise RuntimeError("build finished but Voyage.app was not found")
            self._boot()
            self._run(["xcrun", "simctl", "install", self.udid(), str(app)])
            self._log("installed " + app.name)
        self._background(work)

    def launch(self):
        def work():
            self._boot()
            self._run(["xcrun", "simctl", "launch", "--terminate-running-process",
                       self.udid(), BUNDLE_ID, *self.launch_args()])
        self._background(work)

    def screenshot(self):
        def work():
            QA_DIR.mkdir(exist_ok=True)
            path = QA_DIR / f"launcher-{datetime.now():%Y%m%d-%H%M%S}.png"
            self._run(["xcrun", "simctl", "io", self.udid(), "screenshot", str(path)])
            self._log("saved " + str(path.relative_to(ROOT)))
        self._background(work)

    def record_preview(self):
        def work():
            name = self.device.get().split("  (")[0]
            self._run([str(ROOT / "scripts" / "record_app_preview.sh"), "--device", name])
        self._background(work)

    def open_qa(self):
        QA_DIR.mkdir(exist_ok=True)
        subprocess.Popen(["open", str(QA_DIR)])

    # MARK: Plumbing

    def _boot(self):
        subprocess.run(["xcrun", "simctl", "boot", self.udid()], capture_output=True)
        subprocess.run(["open", "-a", "Simulator"], capture_output=True)
        self._run(["xcrun", "simctl", "bootstatus", self.udid(), "-b"], quiet=True)

    def _run(self, cmd, quiet=False):
        self._log("$ " + " ".join(cmd if not quiet else cmd[:3] + ["…"]))
        proc = subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        tail = []
        for line in proc.stdout:
            line = line.rstrip()
            tail = (tail + [line])[-40:]
            if not quiet or re.search(r"error:|BUILD (SUCCEEDED|FAILED)|warning: .*Voyage/", line):
                self._log(line)
        if proc.wait() != 0:
            for line in tail[-12:]:
                self._log(line)
            raise RuntimeError(f"{cmd[0]} exited {proc.returncode}")

    def _background(self, fn):
        if self.busy:
            self._log("still working on the previous action")
            return
        self.busy = True
        for b in self.buttons:
            b.state(["disabled"])

        def run():
            try:
                fn()
                self._log("done")
            except Exception as error:  # surfaced in the log, never a dead button
                self._log("✗ " + str(error))
            finally:
                self.log_queue.put(None)
        threading.Thread(target=run, daemon=True).start()

    def _log(self, text):
        self.log_queue.put(text)

    def _drain_log(self):
        try:
            while True:
                item = self.log_queue.get_nowait()
                if item is None:
                    self.busy = False
                    for b in self.buttons:
                        b.state(["!disabled"])
                    continue
                self.log.configure(state="normal")
                self.log.insert("end", item + "\n")
                self.log.see("end")
                self.log.configure(state="disabled")
        except queue.Empty:
            pass
        self.after(100, self._drain_log)


if __name__ == "__main__":
    if sys.platform != "darwin":
        sys.exit("Voyage Launcher drives the iOS simulator and needs macOS with Xcode.")
    Launcher().mainloop()
