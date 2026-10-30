This offline fixture executes the production completed-playlist Fetch handler,
Core, initialization gate, Protocol, timing adapter and Server through real
rolling source epochs 27/28/29 and independent local epochs 0/1/2. It checks
complete exact projected video/audio GET and HEAD responses, sanitized cues,
source microseconds, same-MAP timestamp resets, immutable publications,
held initialization leases, malformed optional UTC fallback and typed cleanup.

Only native completed-file/event primitives, socket IO and the device decoder
decision are substituted. All framing, source identity, initialization approval
ordering, conversion, publication and timing decisions remain production code.
The native network is never called. The copied corpus/provenance comes from the
existing synthetic epoch integration fixture and retains its independent binary
split goldens and SHA256. This is neither actual decoder approval nor seamless
physical Roku playback evidence.
