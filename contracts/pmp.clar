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
