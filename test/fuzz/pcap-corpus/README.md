# Classic-PCAP fuzz seeds

These hexadecimal fixtures are handcrafted project inputs. They contain no
captured traffic, personal information, or third-party bytes and are licensed
under Apache-2.0 with the rest of Saint Shield.

The corpus covers both byte orders, both timestamp resolutions, an empty valid
capture, truncated record data, malformed record lengths, and an unsupported
PCAPNG signature. `tools/m1/decode-pcap-seeds.py` converts each checked-in hex
file to raw input before replay or fuzzing.
