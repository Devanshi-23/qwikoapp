/// The scripted demos from plan section 6. "Run scenario" resets the demo
/// data, applies [DemoScenario.setup] and shows [DemoScenario.steps] as
/// hints; the presenter does the rest in the app.
enum DemoScenario {
  happyPath('Happy path, prepaid', 'Verified rider at lunch peak', [
    'Go online on Home',
    'Accept the offer by sliding',
    'Arrive at the store, tick the items, slide "Picked up"',
    'Arrive at the customer and enter the code from Demo controls',
    'See the completion screen and milestone progress',
  ], usesTrip: true),
  codWithChange('COD with change', 'Cash on delivery order', [
    'Go online, then Offers → "Send cash on delivery offer"',
    'Accept, pick up and arrive at the customer',
    'Enter ₹500 received and check the change shown',
    'Deliver; cash in hand goes up by the order amount',
  ], usesTrip: true),
  codByUpi('COD paid by UPI', 'UPI fails once', [
    'Go online, then Offers → "Send cash on delivery offer"',
    'At the customer, choose UPI and show the demo QR',
    'The first payment fails; turn off "UPI payments fail" and retry',
    'Deliver',
  ], usesTrip: true),
  timeoutAndDecline('Offer timeout and decline', 'Online, no trip', [
    'Offers → "Send offer that expires in 5 s" and let it expire',
    'Send another offer and decline it with "Too far"',
    'Open Performance: acceptance rate drops',
  ]),
  batched('Batched order', 'Online, no trip', [
    'Offers → "Send batched offer" and accept',
    'Pick up both orders at the store',
    'Deliver drop 1, then drop 2',
    'Completion shows the batch bonus',
  ], usesTrip: true),
  storeDelay('Store delay and missing item', 'Accepted order at the store', [
    'At the store, "Report an issue" → Order not ready',
    'Wait (or "Skip store wait"); waiting pay accrues',
    'Report "Item missing", pick the item and continue without it',
    'The amount to collect is adjusted',
  ], usesTrip: true),
  customerUnreachable('Customer not reachable', 'Customer never answers', [
    'Accept an order and pick it up',
    'At the customer, call twice (no answer) and wait 5 minutes',
    'Mark undeliverable and return to the store',
    'Completion shows partial pay',
  ], usesTrip: true),
  wrongAddress('Wrong address', 'Customer shares a new location', [
    'Accept an order and pick it up',
    'At the drop, "Can\'t find address" and request location',
    'The customer shares a new pin; the route updates',
    'Deliver at the new pin',
  ], usesTrip: true),
  otpLockout('Wrong OTP lockout', 'At the customer', [
    'Enter a wrong code 3 times',
    'Wait out the 30 s lockout',
    'Enter the code from Demo controls and deliver',
  ], usesTrip: true),
  photoProof('Contactless photo proof', 'Leave-at-door order', [
    'At the customer choose "Leave at door"',
    'Take or use a sample photo, then retake it',
    'Deliver with the photo',
  ], usesTrip: true),
  cancelledMidRoute('Cancelled mid-route', 'Heading to the customer', [
    'Accept an order and pick it up',
    'Active order → "Customer cancels the order"',
    'See compensation and return instructions',
  ], usesTrip: true),
  blockedOnline(
    'Blocked from going online',
    'Expired licence and ₹2,150 cash in hand',
    [
      'Home shows 2 blockers instead of the toggle',
      'Fix the licence (upload a new one)',
      'Deposit cash',
      'Go online',
    ],
  ),
  payoutJourney('Payout journey', 'Withdrawable balance', [
    'Earnings → Withdraw now → confirm',
    'Payouts shows processing, then paid after ~20 s',
    'A second instant withdrawal today is blocked',
  ]),
  payoutFailure('Payout failure', 'Bank rejects payouts', [
    'Earnings → Withdraw now → confirm',
    'The payout fails with a reason; money returns to the balance',
    'Turn off "Payouts fail at the bank", then Retry on Payouts',
  ]),
  incentiveAchieved('Incentive achieved', 'Close to a daily milestone', [
    'Check the milestone card on Home',
    'Deliver orders until the next tier',
    'See "You earned ₹X" and the notification',
  ], usesTrip: true),
  rainMode('Rain mode', 'Raining in your zone', [
    'Home shows the rain bonus',
    'Safety shows the rain advisory',
    'Deliver an order to earn the rain bonus',
  ]),
  sos('SOS', 'On a delivery', [
    'Open Safety (SOS button on the active order)',
    'Hold SOS 3 s, then cancel within the countdown (nothing logged)',
    'Hold again and let it send; tap "I\'m safe now"',
  ]),
  offlineNetwork('Simulated offline network', 'Online, any screen', [
    'Turn off "Network available"',
    'The banner shows; server actions are disabled with a reason',
    'Delivery steps queue; turn the network on to sync',
  ]),
  onboarding('New partner onboarding', 'New sign-up account', [
    'Account state → New sign-up → Switch account',
    'Complete KYC and submit',
    'On the pending screen, "Simulate approval" → Home',
  ]),
  gpsLost('GPS lost', 'Heading to the store', [
    'Accept an order',
    'Simulation → "Lose GPS for 20 s"',
    'The banner shows the last position, then recovers',
  ], usesTrip: true),
  cancelledBeforePickup('Cancelled before pickup', 'Heading to the store', [
    'Accept an order',
    'Active order → "Customer cancels the order"',
    'See ₹15 compensation and return Home, still online',
  ], usesTrip: true),
  customerRefuses('Customer refuses order', 'At the customer, COD', [
    'Send a cash on delivery offer, accept and pick up',
    'At the customer, "Customer refused" with a reason',
    'Return to the store; partial pay is shown',
  ], usesTrip: true),
  cantContinue("Rider can't continue", 'After pickup', [
    'Pick up an order',
    'Report "I can\'t continue · Vehicle breakdown"',
    'Meet the handover rider and confirm "Handed over"',
  ], usesTrip: true),
  cashLimitNear('Cash limit near', '₹1,850 cash in hand', [
    'Go online, then "Send cash on delivery offer"',
    'The offer warns and Accept is disabled; decline',
    '"Send prepaid offer" and accept normally',
  ]),
  batchWithFailure('Batch with one failure', 'Customer never answers', [
    'Accept a batched offer and pick up both',
    'Drop 1 is unreachable: mark undeliverable, continue',
    'Deliver drop 2, return drop 1; no batch bonus',
  ], usesTrip: true),
  weeklyPayout('Weekly payout', 'Withdrawable balance', [
    'Money → "Run weekly payout now"',
    'Payouts shows the weekly payout processing, then paid',
    'A notification confirms it',
  ]);

  const DemoScenario(
    this.title,
    this.setup,
    this.steps, {
    this.usesTrip = false,
  });

  final String title;
  final String setup;
  final List<String> steps;

  /// Runs at 5× so the scenario fits in a few minutes.
  final bool usesTrip;

  int get number => index + 1;
}
