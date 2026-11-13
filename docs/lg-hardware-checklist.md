# LG webOS hardware checklist

Run on a real LG TV (2018 or newer). Record pass/fail and notes for each line.
Test on both an Android phone and an iPhone.

**Setup**
- [ ] Phone and TV are on the same Wi-Fi network.
- [ ] On the TV, enable "Turn on via Wi-Fi" (Settings > General > Devices/Network) so Wake-on-LAN can work.

**Discovery and pairing**
- [ ] iPhone: the Local Network permission prompt appears on first launch; allow it.
- [ ] The TV appears in the list within about 4 seconds.
- [ ] Tapping it shows "Accept the prompt on your TV"; the prompt appears on the TV.
- [ ] Accepting opens the remote. Force-quit and reopen: reconnects with no new prompt.
- [ ] Denying the prompt shows a Retry screen; Retry shows the prompt again.
- [ ] Add by IP (with the TV's IP) works when discovery is skipped.

**Keys**
- [ ] Up, down, left, right, OK, back, home, menu all work.
- [ ] Volume up/down, mute, channel up/down work.
- [ ] Holding volume or an arrow repeats and stops when released.
- [ ] Mute toggles (first press mutes, second unmutes).
- [ ] Pairing succeeds with the current permission list (includes CONTROL_MOUSE_AND_KEYBOARD). If the TV rejects the manifest or the d-pad never connects, note the TV's exact error text.

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
