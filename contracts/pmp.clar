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
;; Check if enough time has passed since last ping
(define-private (can-ping-now (last-ping-block uint))
 (>= (- block-height last-ping-block) MAX-PING-FREQUENCY)
)


;; Validate asset name format
(define-private (is-asset-name-valid (asset (string-ascii 10)))
 (and
   (> (len asset) u0)
   (<= (len asset) u10)
 )
)


;; Update source reliability score after submission
(define-private (update-source-reliability (source principal) (was-successful bool))
 (match (map-get? price-sources { source: source })
   source-data
   (let (
     (new-total (+ (get total-submissions source-data) u1))
     (new-successful (if was-successful
                       (+ (get successful-submissions source-data) u1)
                       (get successful-submissions source-data)))
     (new-score (calculate-reliability-score new-successful new-total))
   )
     (map-set price-sources
       { source: source }
       (merge source-data {
         total-submissions: new-total,
         successful-submissions: new-successful,
         reliability-score: new-score,
         last-submission-block: block-height
       })
     )
     true
   )
   false
 )
)


;; public functions
;; Submit new price data from authorized sources
(define-public (submit-price-data (asset (string-ascii 10)) (price uint) (confidence uint) (volume uint))
 (let ((caller tx-sender))
   ;; Validate contract is active
   (asserts! (is-contract-active) ERR-CONTRACT-PAUSED)
   ;; Validate asset name
   (asserts! (is-asset-name-valid asset) ERR-INVALID-PRICE)
   ;; Validate price
   (asserts! (is-price-valid price) ERR-INVALID-PRICE)
   ;; Validate confidence level (0-100)
   (asserts! (<= confidence u100) ERR-INVALID-PERCENTAGE)
 ;; Check if source is authorized
   (asserts! (is-source-reliable caller u1) ERR-UNAUTHORIZED)
  
   ;; Store price data
   (map-set price-data
     { asset: asset, source: caller }
     {
       price: price,
       timestamp: block-height,
       block-height: block-height,
       confidence: confidence,
       volume: volume,
       is-verified: true
     }
   )
  
   ;; Update source reliability
   (update-source-reliability caller true)
  
   ;; Check if circuit breaker should trigger
   (if (should-trigger-circuit-breaker asset price)
     (map-set circuit-breakers
       { asset: asset }
       {
         is-triggered: true,
         trigger-price: price,
         trigger-block: block-height,
         trigger-reason: "Price threshold exceeded",
         cooldown-period: BLOCKS-PER-DAY,
         reset-block: (+ block-height BLOCKS-PER-DAY)
       }
     )
     true ;; Continue normal operation
   )
  
   (ok true)
 )
)


;; Create or update asset monitoring configuration
(define-public (setup-asset-monitor (asset (string-ascii 10)) (upper-threshold uint) (lower-threshold uint) (percentage-threshold uint))
(let ((caller tx-sender))
   ;; Validate contract is active
   (asserts! (is-contract-active) ERR-CONTRACT-PAUSED)
   ;; Validate asset name
   (asserts! (is-asset-name-valid asset) ERR-INVALID-PRICE)
   ;; Validate thresholds
   (asserts! (is-price-valid upper-threshold) ERR-INVALID-PRICE)
   (asserts! (is-price-valid lower-threshold) ERR-INVALID-PRICE)
   (asserts! (> upper-threshold lower-threshold) ERR-INVALID-PRICE)
   (asserts! (<= percentage-threshold MAX-PERCENTAGE-CHANGE) ERR-INVALID-PERCENTAGE)
   (asserts! (>= percentage-threshold MIN-PERCENTAGE-CHANGE) ERR-INVALID-PERCENTAGE)
  
   ;; Set up monitoring configuration
   (map-set asset-monitors
     { asset: asset }
     {
       upper-threshold: upper-threshold,
       lower-threshold: lower-threshold,
       percentage-change-threshold: percentage-threshold,
       is-active: true,
       alert-count: u0,
       last-alert-block: u0,
       owner: caller
     }
   )
  
   ;; Initialize asset metadata if not exists
   (if (is-none (map-get? asset-metadata { asset: asset }))
     (map-set asset-metadata
       { asset: asset }
       {
         full-name: asset,
         decimals: STX-DECIMALS,
         is-active: true,
         min-price: lower-threshold,
         max-price: upper-threshold,
         circuit-breaker-threshold: (* upper-threshold u5), ;; 5x upper threshold
         total-monitors: u1
       }
     )
   ;; Update existing metadata
     (match (map-get? asset-metadata { asset: asset })
       existing-data
       (map-set asset-metadata
         { asset: asset }
         (merge existing-data {
           total-monitors: (+ (get total-monitors existing-data) u1)
         })
       )
       false
     )
   )
  
   (ok true)
 )
)


;; Subscribe to price alerts for an asset
(define-public (subscribe-to-alerts (asset (string-ascii 10)) (threshold-up uint) (threshold-down uint) (notification-type uint))
 (let ((caller tx-sender))
   ;; Validate contract is active
   (asserts! (is-contract-active) ERR-CONTRACT-PAUSED)
   ;; Validate subscription parameters
   (asserts! (is-subscription-valid threshold-up threshold-down notification-type) ERR-INVALID-PRICE)
   ;; Validate asset exists
   (asserts! (is-some (map-get? asset-metadata { asset: asset })) ERR-NOT-FOUND)
  
   ;; Check if subscription already exists
   (asserts! (is-none (map-get? user-subscriptions { user: caller, asset: asset })) ERR-ALREADY-EXISTS)
  
   ;; Create subscription
   (map-set user-subscriptions
     { user: caller, asset: asset }
     {
       notification-type: notification-type,
       threshold-up: threshold-up,
       threshold-down: threshold-down,
       is-active: true,
       subscription-fee-paid: u0,
     expiry-block: (+ block-height (* BLOCKS-PER-DAY u30)) ;; 30 days expiry
     }
   )
  
   (ok true)
 )
)
;; Trigger price alert/ping when thresholds are met
(define-public (trigger-price-ping (asset (string-ascii 10)) (old-price uint) (new-price uint) (trigger-type uint))
 (let (
   (caller tx-sender)
   (ping-id (generate-ping-id))
 )
   ;; Validate contract is active
   (asserts! (is-contract-active) ERR-CONTRACT-PAUSED)
   ;; Validate caller is authorized source
   (asserts! (is-source-reliable caller u50) ERR-UNAUTHORIZED)
   ;; Validate prices
   (asserts! (is-price-valid old-price) ERR-INVALID-PRICE)
   (asserts! (is-price-valid new-price) ERR-INVALID-PRICE)
   ;; Validate trigger type (1=threshold, 2=percentage, 3=emergency)
   (asserts! (and (>= trigger-type u1) (<= trigger-type u3)) ERR-INVALID-PERCENTAGE)
  
   ;; Check if asset monitor exists and is active
   (match (map-get? asset-monitors { asset: asset })
     monitor-data
     (begin
       (asserts! (get is-active monitor-data) ERR-NOT-FOUND)
       ;; Check if enough time has passed since last alert
       (asserts! (can-ping-now (get last-alert-block monitor-data)) ERR-THRESHOLD-NOT-MET)
      
       ;; Determine severity based on price change
       (let (
         (change-percentage (calculate-percentage-change old-price new-price))
         (severity (if (>= (if (>= change-percentage 0)
                             (to-uint change-percentage)
                             (to-uint (- change-percentage))) u1000) ;; 10%
                      u4 ;; Critical
                      (if (>= (if (>= change-percentage 0)
                                (to-uint change-percentage)
                                (to-uint (- change-percentage))) u500) ;; 5%
                         u3 ;; High
                         (if (>= (if (>= change-percentage 0)
                                   (to-uint change-percentage)
                                   (to-uint (- change-percentage))) u200) ;; 2%
                            u2 ;; Medium
                            u1)))) ;; Low
       )
         ;; Record ping in history
         (map-set ping-history
           { ping-id: ping-id }
           {
             asset: asset,
             trigger-type: trigger-type,
             old-price: old-price,
             new-price: new-price,
             block-height: block-height,
             affected-users: u1, ;; TODO: Count actual affected users
             severity: severity
           }
         )
        
         ;; Update monitor with new alert
         (map-set asset-monitors
           { asset: asset }
           (merge monitor-data {
             alert-count: (+ (get alert-count monitor-data) u1),
             last-alert-block: block-height
           })
         )
        
         ;; Store price history
         (map-set price-history
           { asset: asset, block-height: block-height }
           {
             price: new-price,
            change-percentage: change-percentage,
             volume: u0, ;; TODO: Get actual volume
             volatility-score: u0 ;; TODO: Calculate from recent history
           }
         )
        
         (ok ping-id)
       )
     )
     ERR-NOT-FOUND
   )
 )
)
;; Add authorized price source (admin only)
(define-public (add-price-source (source principal) (initial-stake uint))
 (let ((caller tx-sender))
   ;; Check admin permissions
   (asserts! (or (is-contract-owner caller) (has-admin-permission caller u3)) ERR-UNAUTHORIZED)
   ;; Validate contract is active
   (asserts! (is-contract-active) ERR-CONTRACT-PAUSED)
   ;; Check if source already exists
   (asserts! (is-none (map-get? price-sources { source: source })) ERR-ALREADY-EXISTS)
  
   ;; Add price source
   (map-set price-sources
     { source: source }
     {
       is-authorized: true,
       reliability-score: u50, ;; Default starting score
       total-submissions: u0,
       successful-submissions: u0,
       last-submission-block: u0,
       stake-amount: initial-stake
     }
   )
  
   ;; Initialize stake if provided
   (if (> initial-stake u0)
   (map-set source-stakes
       { source: source }
       {
         staked-amount: initial-stake,
         lock-period: BLOCKS-PER-DAY,
         unlock-block: (+ block-height BLOCKS-PER-DAY),
         earned-rewards: u0,
         penalty-count: u0,
         last-reward-block: u0
       }
     )
     true
   )
  
   (ok true)
 )
)

;; Pause/unpause contract (admin only)
(define-public (set-contract-status (new-status uint))
 (let ((caller tx-sender))
   ;; Check admin permissions
   (asserts! (or (is-contract-owner caller) (has-admin-permission caller u4)) ERR-UNAUTHORIZED)
   ;; Validate status
   (asserts! (and (>= new-status u1) (<= new-status u3)) ERR-INVALID-PERCENTAGE)
  
   ;; Update contract status
   (var-set contract-status new-status)
  
   ;; Record emergency block if setting to emergency status
   (if (is-eq new-status STATUS-EMERGENCY)
     (var-set last-emergency-block block-height)
     true
   )
  
   (ok true)
 )
)


;; Get price data for an asset from a specific source
(define-read-only (get-price-data (asset (string-ascii 10)) (source principal))
 (map-get? price-data { asset: asset, source: source })
)


;; Get latest price history for an asset
(define-read-only (get-price-history (asset (string-ascii 10)) (block-height-lookup uint))
 (map-get? price-history { asset: asset, block-height: block-height-lookup })
)


;; Get asset monitoring configuration
(define-read-only (get-asset-monitor (asset (string-ascii 10)))
 (map-get? asset-monitors { asset: asset })
)


;; Get user subscription details
(define-read-only (get-user-subscription (user principal) (asset (string-ascii 10)))
 (map-get? user-subscriptions { user: user, asset: asset })
)


;; Get price source information
(define-read-only (get-price-source (source principal))
 (map-get? price-sources { source: source })
)


;; Get contract status
(define-read-only (get-contract-status)
 {
   status: (var-get contract-status),
   total-pings: (var-get total-pings),
   last-emergency-block: (var-get last-emergency-block),
   monitoring-enabled: (var-get monitoring-enabled)
 }
)
