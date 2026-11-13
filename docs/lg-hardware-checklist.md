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
- [ ] After the first successful pairing, the TV's MAC is captured automatically (check: power the TV off, then press Power in the app; it should wake without you ever typing a MAC). If it isn't captured, note the TV model and webOS version; the connection-info reply may differ and the parser needs adjusting.
- [ ] Power turns the TV off.
- [ ] With the TV off and its MAC saved (Add by IP, MAC field), Power turns it on via Wake-on-LAN.
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
