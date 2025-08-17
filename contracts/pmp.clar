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
