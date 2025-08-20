;; price-monitor-ping
;; A smart contract for monitoring price changes and triggering alerts/pings


;; constants
;; Error codes
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INVALID-PRICE (err u101))
(define-constant ERR-PRICE-TOO-OLD (err u102))
(define-constant ERR-THRESHOLD-NOT-MET (err u103))
(define-constant ERR-ALREADY-EXISTS (err u104))
(define-constant ERR-NOT-FOUND (err u105))
(define-constant ERR-INVALID-PERCENTAGE (err u106))
(define-constant ERR-INSUFFICIENT-BALANCE (err u107))
(define-constant ERR-CONTRACT-PAUSED (err u108))
(define-constant ERR-INVALID-TIMESTAMP (err u109))


;; Contract configuration
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-PRICE-SOURCES u10)
(define-constant MIN-PRICE-THRESHOLD u1) ;; Minimum price in micro-STX
(define-constant MAX-PRICE-THRESHOLD u1000000000000) ;; Maximum price in micro-STX (1M STX)
(define-constant PRICE-VALIDITY-PERIOD u144) ;; Price valid for 144 blocks (~24 hours)
(define-constant MAX-PERCENTAGE-CHANGE u10000) ;; 100% in basis points (10000 = 100%)
(define-constant MIN-PERCENTAGE-CHANGE u100) ;; 1% in basis points (100 = 1%)
;; Time constants
(define-constant BLOCKS-PER-HOUR u6) ;; Approximate blocks per hour
(define-constant BLOCKS-PER-DAY u144) ;; Approximate blocks per day
(define-constant MAX-PING-FREQUENCY u6) ;; Minimum blocks between pings


;; Precision constants
(define-constant PRECISION-MULTIPLIER u1000000) ;; 6 decimal places for price calculations
(define-constant BASIS-POINTS-MULTIPLIER u10000) ;; For percentage calculations (100% = 10000)


;; Asset constants
(define-constant STX-DECIMALS u6)
(define-constant DEFAULT-ASSET-NAME "STX")


;; Status constants
(define-constant STATUS-ACTIVE u1)
(define-constant STATUS-PAUSED u2)
(define-constant STATUS-EMERGENCY u3)


;; data maps and vars
;; Contract state variables
(define-data-var contract-status uint STATUS-ACTIVE)
(define-data-var total-pings uint u0)
(define-data-var last-emergency-block uint u0)
(define-data-var monitoring-enabled bool true)


;; Price data storage
(define-map price-data
 { asset: (string-ascii 10), source: principal }
 {
   price: uint,
   timestamp: uint,
   block-height: uint,
   confidence: uint, ;; Confidence level (0-100)
   volume: uint,
   is-verified: bool
 }
)


;; Historical price tracking for trend analysis
(define-map price-history
 { asset: (string-ascii 10), block-height: uint }
 {
   price: uint,
   change-percentage: int, ;; Can be negative
   volume: uint,
   volatility-score: uint
 }
)


;; Price monitoring configurations per asset
(define-map asset-monitors
 { asset: (string-ascii 10) }
 {
  upper-threshold: uint,
   lower-threshold: uint,
   percentage-change-threshold: uint,
   is-active: bool,
   alert-count: uint,
   last-alert-block: uint,
   owner: principal
 }
)


;; Authorized price sources and their reliability scores
(define-map price-sources
 { source: principal }
 {
   is-authorized: bool,
   reliability-score: uint, ;; 0-100 based on historical accuracy
   total-submissions: uint,
   successful-submissions: uint,
   last-submission-block: uint,
   stake-amount: uint
 }
)


;; User subscriptions for price alerts
(define-map user-subscriptions
 { user: principal, asset: (string-ascii 10) }
 {
   notification-type: uint, ;; 1=email, 2=webhook, 3=on-chain
   threshold-up: uint,
   threshold-down: uint,
   is-active: bool,
   subscription-fee-paid: uint,
   expiry-block: uint
 }
)
;; Ping/Alert history for analytics
(define-map ping-history
 { ping-id: uint }
 {
   asset: (string-ascii 10),
   trigger-type: uint, ;; 1=threshold, 2=percentage, 3=emergency
   old-price: uint,
   new-price: uint,
   block-height: uint,
   affected-users: uint,
   severity: uint ;; 1=low, 2=medium, 3=high, 4=critical
 }
)


;; Asset metadata and configuration
(define-map asset-metadata
 { asset: (string-ascii 10) }
 {
   full-name: (string-ascii 50),
   decimals: uint,
   is-active: bool,
   min-price: uint,
   max-price: uint,
   circuit-breaker-threshold: uint, ;; Emergency stop threshold
   total-monitors: uint
 }
)


;; Governance and admin controls
(define-map admin-permissions
 { admin: principal }
 {
   can-pause-contract: bool,
   can-add-sources: bool,
   can-modify-thresholds: bool,
   can-emergency-stop: bool,
   permission-level: uint ;; 1=read, 2=write, 3=admin, 4=super-admin
 }
)


;; Performance metrics and analytics
(define-map performance-metrics
 { metric-type: (string-ascii 20), period: uint }
 {
   value: uint,
   timestamp: uint,
   metadata: (string-ascii 100)
 }
)
;; Staking and incentive system for price sources
(define-map source-stakes
 { source: principal }
 {
   staked-amount: uint,
   lock-period: uint,
   unlock-block: uint,
   earned-rewards: uint,
   penalty-count: uint,
   last-reward-block: uint
 }
)


;; Circuit breaker for emergency situations
(define-map circuit-breakers
 { asset: (string-ascii 10) }
 {
   is-triggered: bool,
   trigger-price: uint,
   trigger-block: uint,
   trigger-reason: (string-ascii 50),
   cooldown-period: uint,
   reset-block: uint
 }
)


;; Cross-chain price data (for future expansion)
(define-map cross-chain-prices
 { asset: (string-ascii 10), chain: (string-ascii 20) }
 {
   price: uint,
   bridge-fee: uint,
   last-sync-block: uint,
   is-synced: bool,
   price-deviation-percentage: int
 }
)


;; private functions
;; Helper function to check if user is contract owner
(define-private (is-contract-owner (user principal))
 (is-eq user CONTRACT-OWNER)
)
;; Helper function to check if contract is active
(define-private (is-contract-active)
 (is-eq (var-get contract-status) STATUS-ACTIVE)
)


;; Helper function to validate price within acceptable range
(define-private (is-price-valid (price uint))
 (and
   (>= price MIN-PRICE-THRESHOLD)
   (<= price MAX-PRICE-THRESHOLD)
   (> price u0)
 )
)


;; Helper function to check if price data is still fresh
(define-private (is-price-fresh (timestamp uint))
 (let ((current-block block-height))
   (<= (- current-block timestamp) PRICE-VALIDITY-PERIOD)
 )
)


;; Calculate percentage change between two prices (returns int, can be negative)
(define-private (calculate-percentage-change (old-price uint) (new-price uint))
 (if (is-eq old-price u0)
   0 ;; Return 0 if old price is zero to avoid division by zero
   (let (
     (price-diff (if (>= new-price old-price)
                    (- new-price old-price)
                    (- old-price new-price)))
     (percentage (* (/ (* price-diff BASIS-POINTS-MULTIPLIER) old-price) u1))
     (is-positive (>= new-price old-price))
   )
     (if is-positive
       (to-int percentage)
       (- (to-int percentage))
     )
   )
 )
)
;; Check if price change exceeds threshold
(define-private (exceeds-threshold (old-price uint) (new-price uint) (threshold uint))
 (let ((change-percentage (calculate-percentage-change old-price new-price)))
   (>= (if (>= change-percentage 0)
         (to-uint change-percentage)
         (to-uint (- change-percentage)))
       threshold)
 )
)


;; Validate admin permissions for specific actions
(define-private (has-admin-permission (user principal) (permission-type uint))
 (match (map-get? admin-permissions { admin: user })
   admin-data
   (let ((level (get permission-level admin-data)))
     (or
       (is-eq level u4) ;; Super admin has all permissions
       (and (is-eq permission-type u1) (>= level u1)) ;; Read permission
       (and (is-eq permission-type u2) (>= level u2)) ;; Write permission
       (and (is-eq permission-type u3) (>= level u3)) ;; Admin permission
     )
   )
   false ;; No permissions if not found
 )
)


;; Calculate reliability score based on successful submissions
(define-private (calculate-reliability-score (successful uint) (total uint))
 (if (is-eq total u0)
   u50 ;; Default score for new sources
   (let ((score (/ (* successful u100) total)))
     (if (> score u100) u100 score) ;; Cap at 100
   )
 )
)
;; Check if price source is authorized and reliable
(define-private (is-source-reliable (source principal) (min-reliability uint))
 (match (map-get? price-sources { source: source })
   source-data
   (and
     (get is-authorized source-data)
     (>= (get reliability-score source-data) min-reliability)
   )
   false
 )
)


;; Calculate volatility score based on price history
(define-private (calculate-volatility-score (price-changes (list 10 int)))
 (let (
   (sum-squares (fold + (map square-int price-changes) u0))
   (count (len price-changes))
 )
   (if (is-eq count u0)
     u0
     (/ sum-squares count) ;; Simple volatility calculation
   )
 )
)


;; Helper function to square an integer for volatility calculation
(define-private (square-int (x int))
 (let ((abs-x (if (>= x 0) (to-uint x) (to-uint (- x)))))
   (* abs-x abs-x)
 )
)


;; Check if circuit breaker should be triggered
(define-private (should-trigger-circuit-breaker (asset (string-ascii 10)) (price uint))
 (match (map-get? asset-metadata { asset: asset })
   asset-data
   (let ((threshold (get circuit-breaker-threshold asset-data)))
     (or
      (> price (* (get max-price asset-data) u2)) ;; Price more than 2x max
       (< price (/ (get min-price asset-data) u2)) ;; Price less than half min
       (> price threshold) ;; Above circuit breaker threshold
     )
   )
   false
 )
)


;; Validate subscription parameters
(define-private (is-subscription-valid (threshold-up uint) (threshold-down uint) (notification-type uint))
 (and
   (>= threshold-up MIN-PRICE-THRESHOLD)
   (<= threshold-up MAX-PRICE-THRESHOLD)
   (>= threshold-down MIN-PRICE-THRESHOLD)
   (<= threshold-down MAX-PRICE-THRESHOLD)
   (> threshold-up threshold-down) ;; Upper threshold must be higher
   (and (>= notification-type u1) (<= notification-type u3)) ;; Valid notification type
 )
)


;; Generate unique ping ID
(define-private (generate-ping-id)
 (let ((current-pings (var-get total-pings)))
   (var-set total-pings (+ current-pings u1))
   current-pings
 )
)
