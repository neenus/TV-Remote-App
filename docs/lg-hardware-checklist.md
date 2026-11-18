# Hardware checklist (LG webOS and Samsung Tizen)

Run on a real LG TV (2018 or newer). Record pass/fail and notes for each line.
Test on both an Android phone and an iPhone.

**Setup**
- [ ] Phone and TV are on the same Wi-Fi network.
- [ ] On the TV, enable "Turn on via Wi-Fi" (Settings > General > Devices/Network) so Wake-on-LAN can work.

**Discovery and pairing**
- [ ] iPhone: the Local Network permission prompt appears on first launch; allow it.
- [ ] While scanning, the list shows a spinner and "Searching for TVs on your Wi-Fi…"; the TV appears within about 4 seconds; with no TVs, the empty message appears only after the scan ends.
- [ ] Tapping it shows "Accept the prompt on your TV"; the prompt appears on the TV.
- [ ] Accepting opens the remote. Force-quit and reopen: reconnects with no new prompt.
- [ ] "No remote? Use a code instead": the TV shows a code; typing it in the app pairs successfully (this PIN mode is unverified on real TVs; note the TV's behavior if it fails).
- [ ] Denying the prompt shows a Retry screen; Retry shows the prompt again.
- [ ] Add by IP (with the TV's IP) works when discovery is skipped.

**Keys**
- [ ] Up, down, left, right, OK, back, home, menu all work.
- [ ] Volume up/down, mute, channel up/down work.
- [ ] Holding volume or an arrow repeats and stops when released.
- [ ] Rewind, play, pause and fast-forward work while a video is playing (these depend on the app playing it; note which apps respond).
- [ ] Mute toggles (first press mutes, second unmutes).
- [ ] Pairing succeeds with the current permission list (includes CONTROL_MOUSE_AND_KEYBOARD). If the TV rejects the manifest or the d-pad never connects, note the TV's exact error text.

**Input button (top of the remote, next to the keyboard icon)**
- [ ] LG: opens the TV's input list (it needs a new permission, so the TV may ask you to pair again once). Pick an input with the d-pad and OK. Note whether it opens.
- [ ] Samsung (all three types): opens the TV's source list (sends the Source key). Pick an input with the d-pad and OK.

**Typing**
- [ ] Open a search box on the TV (e.g. in YouTube or Netflix): the phone shows a "Type on your TV" box with the keyboard.
- [ ] Typed letters appear in the TV's search field; backspace removes them; Enter submits the search.
- [ ] The box closes by itself when the TV's text field loses focus.
- [ ] The keyboard icon at the top of the remote opens the box manually.
- [ ] After updating the app, pairing may be asked for again (a new permission was added); note what the TV shows.

**Power and wake**
- [ ] MAC address: after pairing, the TV list should stop showing "No MAC address" for the TV (the app asks the TV for it; this needed a new permission, so an already-paired LG may need to be removed (x) and added again). If it still shows the hint, press and hold the TV in the list and type its MAC (LG: Settings > General > About This TV, or your router's device list).
- [ ] After the first successful pairing, the TV's MAC is captured automatically (check: power the TV off, then press Power in the app; it should wake without you ever typing a MAC). If it isn't captured, note the TV model and webOS version; the connection-info reply may differ and the parser needs adjusting.
- [ ] Power turns the TV off.
- [ ] With the TV off and its MAC saved, Power turns it on via Wake-on-LAN. Test it **immediately** and again **after a minute or two**. If it only works in the first few seconds, the TV's network is going to sleep: on the TV turn on All Settings > General > Devices > External Devices > TV On With Mobile > **Turn on via Wi-Fi**, and General > **Quick Start+** if present (names vary by model). A TV connected by network cable wakes far more reliably than one on Wi-Fi.
- [ ] The app sends the wake signal 3 times to the general broadcast, the TV's own network and the TV itself (needed when the TV is on another network range).
- [ ] With no MAC saved and the TV off, Power shows the "No MAC saved" message.

**Resilience**
- [ ] Unplug the TV, then try to connect: a clear error appears within about 5 seconds.
- [ ] Lock the phone for a minute, unlock, press a key: it reconnects and the key works.
- [ ] Change the TV's IP (or reboot the router so it gets a new one) and reopen the saved TV: it finds the new address.

**Latency**
- [ ] Tap to on-screen response feels under about 150 ms. Note any lag.

Report failures with the TV model, webOS version and phone OS.

---

# Samsung (Tizen 2016 or newer)

Unverified on real hardware: the protocol comes from community documentation.

**Pairing**
- [ ] Add the TV by IP (choose Samsung), or find it in the scan (it should appear within about 4 seconds). If the scan misses it, note the model and year.
- [ ] The app shows "Accept the prompt on your TV". The TV shows an "Allow" box for "TV Remote". You must press Allow on the TV's own remote (Samsung has no on-screen code option). If you have no remote, note this; the TV's menu may let you disable the prompt (Device Connection Manager / access notification), which is worth trying.
- [ ] After allowing, the remote opens. Force-quit and reopen: it reconnects without a new prompt (the token was saved).
- [ ] Pressing Deny shows a Retry screen. Samsung TVs may remember a denied device and not prompt again; if so the app says to open Settings > General > External Device Manager > Device Connection Manager > Device List and allow or remove "TV Remote". Note what your TV does.

**Keys**
- [ ] Up, down, left, right, OK, back, home, menu all work.
- [ ] Volume up/down, mute, channel up/down work; holding volume repeats.
- [ ] Rewind, play, pause, fast-forward work during playback.
- [ ] The keyboard icon is greyed out on Samsung (typing isn't supported yet); note whether the TV's own on-screen keyboard works with the d-pad.

**Power and wake**
- [ ] Power turns the TV off.
- [ ] The TV's MAC is captured automatically after connecting (check: with the TV off, Power should wake it, if the TV's "Power on with mobile" or network standby option is enabled).

**Resilience**
- [ ] Unplug the TV, then try to connect: a clear error appears within about 10 seconds.
- [ ] Lock the phone for a minute, unlock, press a key: it reconnects and the key works.
- [ ] Note the TV model, year and whether the app connected on the secure port or fell back to the plain one.

---

# Samsung 2013 or older (legacy protocol, TCP port 55000)

This protocol is what roughly 2010-2013 Samsung TVs speak. 2014-2015 (H and J series) models use a different protocol (see the next section).

Unverified on real hardware. The packet formats were checked against the public samsungctl source, but not against a TV.

**Pairing**
- [ ] Add by IP, choosing "Samsung (2013 or older)" (the scan cannot tell old from new Samsungs).
- [ ] The first time, the TV shows an Allow / Deny box for "TV Remote". You must press Allow with the TV's own remote.
- [ ] After allowing, the remote opens. Close the app and reopen: it connects without another prompt (the TV remembers the device).
- [ ] Deny shows a Retry screen with a message that tells you to choose Allow on the TV.

**Keys**
- [ ] Up, down, left, right, OK, back, menu, volume, mute, channel work.
- [ ] Home opens SmartHub (it sends the SmartHub key on these TVs).
- [ ] Power turns the TV off (these TVs use a different power-off key; power on needs Wake-on-LAN and may not work on this age of TV).
- [ ] Rewind, play, pause, fast-forward during playback.
- [ ] Typing is not supported (the keyboard icon is greyed out).

**Resilience**
- [ ] With the TV unplugged, connecting gives a clear error within about 10 seconds.
- [ ] Note the TV model, year, and whether it showed the Allow prompt.

---

# Samsung 2014-2015 (H and J series: encrypted PIN pairing)

Built from the samsungtvws library and verified against it with test vectors, but **never tried on a real TV yet**. Written for a UN50HU7000 (2014), which answers on ports 8000, 8001 and 8080 and refuses 55000 and 8002.

**Pairing**
- [ ] Add by IP, choosing **Samsung (2014-2015)**.
- [ ] The app says "Enter the code shown on your TV" and the TV shows a PIN screen (4 digits). No remote is needed.
- [ ] Typing the PIN and tapping Pair opens the remote. Note any message the app shows.
- [ ] A wrong PIN shows "That code was not accepted" with Retry; Retry shows a fresh PIN screen.
- [ ] Close the app and reopen: it connects without asking for a PIN again.
- [ ] If keys stop working after a long time or after the TV was reset: remove the TV (the x on its card) and add it again to pair afresh.

**Keys**
- [ ] Up, down, left, right, OK, back, menu, volume, mute, channel.
- [ ] Home opens SmartHub. Power turns the TV off (power on needs Wake-on-LAN and may not work on this age of set).
- [ ] Rewind, play, pause, fast-forward during playback.
- [ ] Typing is not supported (the keyboard icon is greyed out).

**Resilience**
- [ ] Leave the remote open for several minutes without touching it, then press a key: it still works (the app reconnects by itself if the connection dropped).
- [ ] With the TV unplugged, connecting gives a clear error within about 10 seconds.
- [ ] Note any step where the TV shows nothing or the app shows an unexpected message.

---

# Fire TV (ADB over Wi-Fi)

Built from the ADB protocol and verified against the adb_shell library with test vectors (message framing, key blob, token signing). **Never tried on a real Fire TV yet.**

**Set up the Fire TV once**
1. On the Fire TV: Settings > My Fire TV > About, then click the Fire TV Stick's name **seven times** until it says you are a developer (this reveals Developer options).
2. Settings > My Fire TV > Developer options > turn **ADB debugging** ON.
3. Your phone must be on the same network as the Fire TV (it can reach the IoT network if your router allows it).

**Pairing**
- [ ] Add by IP, choosing **Fire TV**.
- [ ] The first time, the app may take a few seconds to make its security key ("Connecting…"), then the Fire TV shows **"Allow USB debugging?"**. Tick "Always allow" and choose **OK** with the Fire TV's own remote. The app shows "Accept the prompt on your TV".
- [ ] After OK the remote opens. Close and reopen the app: it connects without a prompt.
- [ ] With ADB debugging off, the app explains how to switch it on.

**Keys**
- [ ] D-pad, OK, back, home, menu work. Rewind, play, pause, fast-forward work in a video app.
- [ ] Power puts the stick to sleep / wakes it.
- [ ] Volume and mute change the stick's volume (they only affect the TV if your setup passes them on).
- [ ] The Input button and channel buttons are greyed out (not available on Fire TV).
- [ ] Hold the d-pad or volume: it keeps working without lag building up (one command at a time).

**Typing (new: works on Fire TV)**
- [ ] In a search box on the Fire TV, open the keyboard icon (top of the remote) and type: the text appears on the TV; backspace deletes; Enter submits.
- [ ] Note any characters that don't type (only plain ASCII is supported).

**Resilience**
- [ ] Put the stick to sleep and wake it: the next button press reconnects.
- [ ] Note any step where the Fire TV or the app shows something unexpected.

---

# Roku (TVs and players)

Built from Roku's External Control Protocol (plain HTTP on port 8060). **Never tried on a real Roku yet.**

**Setup:** on the Roku, Settings > System > Advanced system settings > **Control by mobile apps** should be **Default** or **Permissive** (the app tells you if it is blocked).

- [ ] Add by IP choosing **Roku**, or find it in the TV list (the scan finds Rokus). No pairing and no code.
- [ ] After connecting, the TV list should stop saying "No MAC address" (read from the Roku automatically).
- [ ] D-pad, OK, back, home work. Menu sends the * options key. Volume and mute work on a Roku TV (not on a Roku stick/box). Channel up/down work on a Roku TV with a tuner.
- [ ] Play and pause both toggle play/pause (Roku has one toggle). Rewind and fast-forward work in a video app.
- [ ] Power turns a Roku TV off/on. With the TV off and a saved MAC, Power can also wake it (Fast TV Start must be on for the network to stay awake).
- [ ] The Input button is greyed out (not available).
- [ ] Typing: in a Roku search box open the keyboard icon (top of the remote) and type; backspace and Enter work.

---

# Android TV / Google TV (Sony, Philips 2018 or newer, TCL, Hisense, Nvidia Shield...)

Built from the Android TV Remote protocol v2 (the one Google's own remote app uses), verified against the androidtvremote2 library with test vectors, and the TLS connection tested against a local server. **Never tried on a real TV yet.** This is the choice **Android TV (Sony, Philips…)** in Add by IP. (Fire TV is not Android TV in this sense: use the Fire TV choice.)

**Pairing**
- [ ] Add by IP choosing **Android TV (Sony, Philips…)**. The first time the app makes a security certificate (a few seconds, "Connecting…").
- [ ] The app says "Enter the code shown on your TV" and the TV shows a **6-character code** (digits 0-9 and letters A-F). No remote is needed. Type it and tap Pair.
- [ ] A wrong code shows "That code was not accepted" (often caught immediately, because the first two characters are a checksum).
- [ ] After pairing the remote opens; close and reopen the app: it connects without asking for a code.
- [ ] If the TV stops accepting the app (for example after a factory reset): remove the TV (x) and add it again.

**Keys**
- [ ] D-pad, OK, back, home, menu work. Volume, mute, channel up/down work (the TV's own volume, if the TV controls it).
- [ ] Input opens the TV's input list. Play, pause, rewind, fast-forward work in a video app.
- [ ] Power toggles the TV (it may not wake a TV that is fully off: use Wake-on-LAN with its MAC).
- [ ] Typing is not supported on these TVs yet (the keyboard icon is greyed out).
- [ ] Leave the remote idle for a minute, then press a key: it reconnects by itself.
