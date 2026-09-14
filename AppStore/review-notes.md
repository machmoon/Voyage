# App Review notes — unified release, September 11, 2026

Owner check before submission: confirm commercial-use rights for the bundled ElevenLabs
announcements. The prior notes flagged the generation plan as unconfirmed. Do not attest
to content rights until that fact is resolved. App Store Connect must also be checked for
its latest build number and review messages before selecting a build.

## Notes for the reviewer

Voyage is a focus timer presented as an airline flight. Routes set the study-session
length; this app does not book travel or claim affiliation with an airline. There is no
account, sign-in, subscription, or in-app purchase.

To try the booking flow, choose a destination on the globe, choose a seat, add or skip
study tasks, and tear the boarding pass. The in-flight screen offers an airplane window
and a route map. Completing a session adds it to the local logbook and passport. Leaving
the app for more than 30 seconds during flight causes a diversion. The app does not block
other apps or enable airplane mode.

The carriers (Voyage Air, Harborline, Ridgeway, Northline, Baywater, and Lantern) are
fictional. Airport names and coordinates describe real places. The bundled announcements
are synthetic speech made for Voyage, rather than recordings of airline crew.

The prior audio background-mode declaration has been removed. Voyage does not request
background audio execution. Audio is a foreground enhancement; the flight timer and
logbook remain usable with sound disabled.

Weather is supplied by Open-Meteo, with credit and its CC BY 4.0 link in Settings. Missing
weather uses an on-device clear-sky fallback. The app does not link WeatherKit. Map and
satellite imagery use Apple MapKit; attribution remains visible in the map views.

Location permission is optional and is used on device to find the nearest supported
airport. The app retains the selected airport code, not a location history. Airport
selection also works manually in Settings. Weather requests use airport and route
coordinates, not the device's location.

Focus-session history is stored locally with SwiftData. There are no advertising or
analytics SDKs. The privacy notice is available at:
https://github.com/machmoon/Voyage/blob/main/PRIVACY.md

## QA instructions for the developer

The simulator-only workflow below is not a control an App Store reviewer can use on an
installed distribution build. Do not paste it as their required review path.

`-VoyageDemoFlight` compresses each leg to one minute. The phase schedule now reserves
nonzero takeoff, climb, cruise, descent, and landing windows. `Load demo history` is a
Debug-only Settings command and is not present in the submitted build. A walkthrough
recording can demonstrate arrival and the logbook without making the reviewer wait for
a full route.

App Store Connect: 1.1 (4) is live since September 13, 2026. The update in review is 1.1.1
(build 6), submitted through `build/submit_update.py` with the 886x1920 app preview from
`scripts/record_app_preview.sh` on the 6.9", 6.5" and 6.1" slots. Build 5 was withdrawn before
review to add the screen-awake fix and the large-text layout fixes.
Contact details and existing listing metadata must be checked in App Store Connect.
