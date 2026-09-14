# Research: pilot-in-training progression, identity apps, and the ADHD evidence

September 14, 2026. Grounded memo for the "pilot in training" idea. Every factual claim carries a
URL. Where a source is a blog, a vendor, or an App Store review, it is labelled as such.

## 1. How real pilot progression works, and what logbook apps do with it

### FAA Part 61 ladder (airplane single-engine)

| Milestone | Gate | Source |
|---|---|---|
| First solo | Not hours: an instructor-written knowledge test, logged pre-solo training, "demonstrated satisfactory proficiency," and a logbook endorsement for the specific make/model, renewed every 90 days | [14 CFR 61.87](https://www.law.cornell.edu/cfr/text/14/61.87) |
| Private pilot | 40 h total, 20 h dual, 10 h solo, 3 h cross-country dual, 3 h night incl. one 100 nm XC and 10 full-stop landings, 3 h instrument, 3 h test prep within the preceding 2 calendar months, 5 h solo XC incl. one 150 nm flight with 3 full-stop landings, 3 full-stop landings at a towered airport | [14 CFR 61.109(a)](https://www.law.cornell.edu/cfr/text/14/61.109) |
| Instrument rating | 50 h XC as PIC, 40 h instrument time (15 h with an instructor), one 250 nm IFR cross-country | [14 CFR 61.65(d)](https://www.law.cornell.edu/cfr/text/14/61.65) |
| Commercial | 250 h total, 100 h PIC, 50 h XC, 20 h training incl. 10 h instrument, one 300 nm solo XC, 5 h night VFR | [14 CFR 61.129(a)](https://www.law.cornell.edu/cfr/text/14/61.129) |
| ATP | 1,500 h total, 500 h XC, 100 h night, 75 h instrument, 250 h PIC | [14 CFR 61.159(a)](https://www.law.cornell.edu/cfr/text/14/61.159) |

Logbook columns are regulated. Each entry must record date, total time, departure/arrival, aircraft
type and ID, safety pilot if any, the kind of experience (solo, PIC, SIC, training received), and
conditions (day/night, actual or simulated instrument). A student pilot may log PIC only when "the
sole occupant of the aircraft" holding a current solo endorsement
([14 CFR 61.51(b), (e)(4)](https://www.law.cornell.edu/cfr/text/14/61.51)).

Two structural facts matter for Voyage. First, the ladder is not one number. Every rating is a
bundle of typed hours (dual, solo, XC, night, instrument) plus a few one-time events (the 150 nm
solo, the towered landings). Second, the first big milestone (solo) is not an hours gate at all; it
is an instructor sign-off and a knowledge check.

### How logbook apps model it

**MyFlightbook** (open source, GPL) is the reference design.
`MyFlightbook.Web/AppCode/Flights/Ratings/MilestoneProgress.cs` defines an abstract
`MilestoneProgress` (`Title`, `RatingSought`, `ComputedMilestones`, a `Refresh()` that runs
`ExamineFlight()` over every logged flight) and a `MilestoneItem` with `Title`, `FARRef`,
`Progress`, `Threshold`, `IsSatisfied`, and a `Type` enum of `AchieveOnce | Count | Time`;
`MilestoneItemDecayable` adds expiring requirements and `MatchingEventID` links an `AchieveOnce`
item to the one flight that satisfied it
([source](https://raw.githubusercontent.com/ericberman/MyFlightbookWeb/master/MyFlightbook.Web/AppCode/Flights/Ratings/MilestoneProgress.cs)).
`PPLRatings.cs` builds 61.109 as roughly 15 items: 40.0 total (Time), 20 dual, 10 solo, 3 night,
3 simulated IMC, 3 test prep (decayable, 2 months), 5 solo XC, 3 dual XC, plus AchieveOnce items for
the 100 nm night XC and the 150 nm solo XC, and Count items for 10 night takeoffs/landings and 3
towered solo takeoffs/landings
([source](https://raw.githubusercontent.com/ericberman/MyFlightbookWeb/master/MyFlightbook.Web/AppCode/Flights/Ratings/PPLRatings.cs)).
The same directory holds per-rating files (`IFRRatings.cs`, `CommRatings.cs`, `ATPRatings.cs`,
`SportRatings.cs`, `Checkrides.cs`) and `RecentAchievements.cs`, which computes non-regulatory
"firsts" such as hours logged, flying-day streak, longest gap without flying, most flights in a day,
distinct aircraft, airports and countries visited, longest and furthest flight
([directory](https://github.com/ericberman/MyFlightbookWeb/tree/master/MyFlightbook.Web/AppCode/Flights/Ratings),
[RecentAchievements.cs](https://raw.githubusercontent.com/ericberman/MyFlightbookWeb/master/MyFlightbook.Web/AppCode/Flights/Ratings/RecentAchievements.cs)).
The site exposes these as "Ratings Progress" and "8710 / IACRA" under a Training tab, and prunes
currencies "for which you have never been current" ([FAQ](https://myflightbook.com/logbook/public/FAQ.aspx)).

**ForeFlight Logbook** ships "Progress Tracking" reports "towards your private pilot certificate or
instrument rating," a Commercial progress report, color-coded recency, and "over sixty endorsement
templates derived from FAA Advisory Circular 61-65H" that instructors sign in-app
([product page](https://foreflight.com/products/logbook/)). **LogTen** frames student progress as
"From your first solo to cross-country flights and rating requirements," with Smart Groups so "you
always know what's completed and what's next," and a built-in 8710 report
([how it works](https://logten.com/how-it-works/)).

Pattern across all three: progress is shown per requirement, not as one bar; regulatory citations
are printed next to each item; one-time events are tracked separately from accumulating time; and
"achievements" (records, streaks, firsts) live in a separate, non-regulatory list.

## 2. Identity and avatar progression in habit apps

**Finch** (4.9, 751K ratings). The bird grows from tiny tasks; a coach's review says "Your bird
friend won't chastise you for missing a day like certain chaotic green owls," goals are "very tiny,"
and the app is "a dopamine machine" of cosmetics
([neurodivergent-coaching.com](https://www.neurodivergent-coaching.com/post/app-reviews-finch-self-care)).
Users name the absence of punishment: "You also don't get penalized/made to feel bad if you don't
complete some goals" ([App Store reviews](https://apps.apple.com/us/app/finch-self-care-pet/id1528595748?see-all=reviews)).
Fits Voyage: growth-only avatar, tiny first steps. Betrays Voyage: nothing structural, though
Finch's cuteness register is off-voice.

**Habitica**. Missed dailies cost HP; in a party, "when you join a group and a boss appears, every
missed habit deals damage to everyone's characters"
([Trophy case study, vendor blog](https://trophy.so/blog/habitica-gamification-case-study)). A
clinician review lists "Must be consistent with your check-ins to earn rewards" as a con and
cautions users prone to gaming addiction
([choosingtherapy.com](https://www.choosingtherapy.com/habitica-app-review/)). Betrays Voyage:
punitive HP and social damage.

**Forest / Flora**. Forest's mechanic is loss: "the flower or shrub... will die if I break the rules
of the app, and will remain on my forest record forever"
([Forest App Store review](https://apps.apple.com/us/app/forest-focus-for-productivity/id866450515?see-all=reviews)).
A reviewer notes the guilt decays: "Month 2+: Forest becomes a timer app. A good one, but just a
timer" ([screentimeindex.com, blog](https://screentimeindex.com/posts/forest-app-review/)). Flora
adds a money pledge donated to Trees for the Future on failure, plus "Flora Care" that plants a real
tree per 24 focused hours
([businessofbusiness.com](https://www.businessofbusiness.com/articles/flora-focus-productivity-app-review/));
users like "a sort-of 'bet' on yourself," and one with "severe ADHD" says it is "the only
time-keeping app that I've stuck with," but others report trees wrongly killed and boredom: "I've
already finished the only two available tours...I'm starting to get bored of the same plants"
([Flora reviews](https://apps.apple.com/us/app/flora-green-focus/id1225155794?see-all=reviews)).
Fits Voyage: real-world tie-in and friends planting together. Betrays Voyage: the dead-tree record.
Voyage already has an honest analogue (diversion) that is data, not shame.

**Duolingo**. Duolingo's own 2017 post: a Streak Wager produced "statistically significant increases
in Day-1, Day-7 and Day-14 user retention, with Day-7 retention showing the greatest improvement at
+14%," and the Weekend Amulet (a streak freeze) made learners "4% more likely to come back a week
later and 5% less likely to lose their streak"; it also admits "learners who binge on Duolingo
lessons were much more likely to abandon the app"
([blog.duolingo.com](https://blog.duolingo.com/how-streaks-keep-duolingo-learners-committed-to-their-language-goals/)).
Independent evidence that streak highlighting works: a 60,000-student RCT in Peru found streak
messages "significantly increased platform use" and improved math achievement for the endline
subsample ([NBER w34173](https://www.nber.org/papers/w34173),
[Econ. of Education Review 2025](https://www.sciencedirect.com/science/article/abs/pii/S0272775725001013)).
Backlash is real and mostly about leagues: "I could tell I was going to get obsessed with my rank in
the leaderboard, and that it would completely derail my attempts to be good to my brain"
([Kotaku, 2019](https://kotaku.com/my-language-learning-app-has-a-leaderboard-and-its-ruin-1837407062)).
Fits Voyage: showing a streak with a freeze. Betrays Voyage: leagues, loss-framed streak nags.

**Fabulous**. Incubated at Duke's behavioral economics lab; the founder-affiliated "Duke study"
claim is flagged as conflicted by outside reviewers
([nibble-app.com](https://nibble-app.com/blog/is-the-fabulous-app-legit)). Its reusable idea is
ritual chaining rather than avatars. Fits Voyage: the boarding sequence is already a ritual; do not
add more.

## 3. Evidence on focus tools for ADHD students

**Externalized time (well supported in theory, thin but positive in trials).** Barkley's factsheet:
EF deficits "are to time what nearsightedness is to spatial vision," so patients should "be assisted
by making time itself more externally represented," with information and motivation "'externalized'
as much as possible... at critical points of performance"
([russellbarkley.org](https://www.russellbarkley.org/factsheets/ADHD_EF_and_SR.pdf)). A 2025
within-subjects study of 44 children aged 7 to 9 found a visual Time Timer lowered anticipatory
anxiety and inattentive behaviors (p = 0.002), with a larger reduction for children with higher
Conners scores, but no change in math scores
([Hallez and Vallier 2025](https://pmc.ncbi.nlm.nih.gov/articles/PMC12731990/)). Small sample,
young children; supportive, not definitive.

**Immediate and real reward (well supported).** Meta-analysis of 37 comparisons, 3,763
participants: people with ADHD pick small immediate over larger delayed rewards with
small-to-medium effect sizes, and "offering real rewards in the SCP almost doubled the odds ratio
for participants with ADHD"
([Marx et al., J. Attention Disorders](https://journals.sagepub.com/doi/10.1177/1087054718772138)).
Sonuga-Barke's delay-aversion account holds that ADHD behavior partly reflects attempts to "create
so-called non-temporal stimulation" that alters the subjective experience of delay
([Antrop et al. 2006](https://acamh.onlinelibrary.wiley.com/doi/10.1111/j.1469-7610.2006.01619.x)).
Implication: the reward must land at landing, and it must be concrete (a stamp you can see), not a
promise of a far tier.

**Stimulation and novelty (moderately supported).** Zentall's optimal-stimulation theory
([1975](https://onlinelibrary.wiley.com/doi/abs/10.1111/j.1939-0025.1975.tb01185.x)) and a 2016
study in which white noise "reduced omission rate in children with ADHD, who were no longer
different from TDC" ([Baijot et al. 2016](https://pmc.ncbi.nlm.nih.gov/articles/PMC4791764/)).
Supports the engine ambience and the changing window.

**Body doubling (emerging, descriptive).** The first academic study surveyed 220 mostly
neurodivergent people; the community defines it as "using the presence of others to start, stay
focused on, or accomplish a task," and a double "can be collocated or remote, recorded or live,
known or a stranger"
([Eagle, Baltaxe-Admony and Ringland, ACM TACCESS 2024](https://dl.acm.org/doi/full/10.1145/3689648)).
No controlled outcome data yet.

**Session length (anecdotal).** ADDitude's Pomodoro-for-teens piece is by an ADHD coach and cites
no research ([ADDitude](https://www.additudemag.com/pomodoro-focus-breaks-teens-adhd/)). Advice
ranges from 10 to 90 minutes ([psychcentral](https://psychcentral.com/adhd/how-to-adapt-the-pomodoro-technique-adhd)).
No credible evidence for a single right length.

**Chunking and proximal goals (well supported, older).** Bandura and Schunk 1981: children given
proximal subgoals "progressed rapidly... and developed a sense of personal efficacy and intrinsic
interest," while "Distal goals had no demonstrable effects"
([Semantic Scholar](https://www.semanticscholar.org/paper/Cultivating-competence,-self-efficacy,-and-interest-Bandura-Schunk/b1e4d476c857333b9a0afdb1428eda27f6d26940)).
CHADD's advice is consistent: break tasks into cross-off-able steps and "Promise yourself a small
reward" ([CHADD](https://chadd.org/for-adults/time-management/)).

**Start friction (clinician consensus, no trials).** Barkley frames ADHD as a performance problem at
the point of performance; coaching sources say to reduce steps between intent and task
([getinflow.io](https://www.getinflow.io/post/task-initiation-strategies-for-adults)).

## 4. What students use and complain about

- **FocusFlight** (4.9, 9.3K). Praise is emotional and about starting: "I was even excited to
  study," "the only focus app that actually made me keep coming back." The ADHD user credits
  ambience. Critique: "it really just becomes a white noise machine"
  ([App Store](https://apps.apple.com/us/app/focusflight-deepfocus-timer/id6648771147?see-all=reviews)).
- **Forest** (4.8, 49K). Wants a Pomodoro with breaks, a working Watch app.
- **Flora** (4.8, 83K). Broken allow-list, false tree deaths, content exhaustion.
- **Study Bunny** (4.7, 21K). "As a busy undergrad and adult with ADHD this has been the greatest
  app for me... I love that it keeps track of every single minute." Complaints are ads
  ([App Store](https://apps.apple.com/us/app/study-bunny-focus-timer/id1478345385?see-all=reviews)).
- **Flip** (4.5, 895). Physical trigger praised; data-loss bug on goal edits.
- **YPT** (4.7, 1.7K). Groups are the draw; rejection of enforcement: "I need an app to track my
  studying, not an app to be my mom"
  ([App Store](https://apps.apple.com/us/app/ypt-yeolpumta/id1441909643?see-all=reviews)).
- **Opal** (4.7, 88K). Billing dark patterns; bypassable blocks
  ([Opal forum](https://community.opalapp.com/t/7-days-into-a-full-year-seems-extreme/955)).

Themes: students reward honest, per-minute records; they punish ads, subscriptions, data loss, and
anything that "moms" them; content exhaustion kills the metaphor apps; nobody asks for leaderboards.

## 5. Synthesis: ranked feature bets

1. **Ratings ladder with typed hours (MyFlightbook model), replacing the miles tiers.** Precedent:
   `PPLRatings.cs` items with `Threshold`/`Progress`/`FARRef` and `AchieveOnce` events. Fit:
   proximal subgoals beat distal ones. Risk: UI complexity; over-literal FAR copy. In Voyage: a
   "Training" page listing Student, Private, Instrument, Commercial, ATP, each as a checklist of
   typed hours and one-time events.
2. **First solo as the first milestone, gated by sessions not hours.** Precedent: 61.87. Fit: a
   near-horizon "solo" after three completed flights lands a real reward fast. Risk: the 90-day
   lapse rule could read as a streak penalty; make it re-earnable silently.
3. **Honest logbook columns as the data surface.** Precedent: 61.51(b) fields; Study Bunny's "keeps
   track of every single minute." In Voyage: Date, Route, Block time, Night, XC, Dual/Solo,
   Diverted; CSV export.
4. **Streak shown, never nagged, with a built-in freeze.** Precedent: Duolingo Weekend Amulet; Peru
   RCT. Risk: any push about a streak crosses into "mom" territory.
5. **Recent Achievements list (non-regulatory firsts).** Precedent: `RecentAchievements.cs`.
6. **Body-double "dual" sessions.** Precedent: TACCESS 2024; YPT groups. Risk: social features are
   where YPT and Flip accumulate bugs and moderation load.
7. **Real-world tie-in for accumulated hours.** Precedent: Flora Care. Risk: cost and a payment
   surface in a free app. Skip unless a partner exists.
8. **Session-length presets that start short and extend.** No evidence for a fixed length; evidence
   for near goals.

**On the pilot-in-training identity.** Make it the replacement for FlyerTier, not a parallel track
or a cosmetic. Miles tiers are a single distal number, the shape Bandura and Schunk found had "no
demonstrable effects"; the ratings ladder converts the same data into a dozen proximal, typed
sub-goals, which is what every real logbook app already builds. Keep the cosmetic unlocks but hang
them off ratings. Do not lead with the 1,500 h ATP: at one hour per school day it is six-plus years
away. Show only the next rating and its remaining items, the way MyFlightbook prunes currencies you
have never held. The trainer avatar is fine as the signer of endorsements; do not let it scold. The
honest analogue to the checkride is already in the app: the landing.

Unresolved: no study tests hours-toward-rating framing for study; the Peru streak RCT is the closest
evidence that highlighting accumulated behavior raises effort.
