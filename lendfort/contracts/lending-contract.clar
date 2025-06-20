;; Bitcoin Bridge Aggregator & Peg Insurance Protocol
;; Combines bridge optimization with Bitcoin peg depeg insurance

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_POOL_NOT_FOUND (err u103))
(define-constant ERR_CLAIM_NOT_FOUND (err u104))
(define-constant ERR_CLAIM_ALREADY_PROCESSED (err u105))
(define-constant ERR_INSUFFICIENT_COVERAGE (err u106))
(define-constant ERR_BRIDGE_NOT_SUPPORTED (err u107))
(define-constant ERR_BATCH_LIMIT_EXCEEDED (err u108))
(define-constant ERR_CLAIM_EXPIRED (err u109))
(define-constant ERR_INVALID_BRIDGE (err u110))

;; Data Variables
(define-data-var total-value-locked uint u0)
(define-data-var insurance-pool-balance uint u0)
(define-data-var protocol-fee-rate uint u25) ;; 0.25% in basis points
(define-data-var claim-counter uint u0)
(define-data-var batch-counter uint u0)
(define-data-var max-batch-size uint u50)
(define-data-var claim-period uint u144) ;; ~24 hours in blocks

;; Data Maps
(define-map user-deposits principal uint)
(define-map user-insurance-stakes principal uint)
(define-map user-bridge-shares principal uint)
(define-map bridge-allocations 
  {bridge: (string-ascii 32)} 
  {allocation-percentage: uint, last-sync: uint, total-bridged: uint, peg-ratio: uint})
(define-map insurance-claims 
  uint 
  {
    claimant: principal,
    amount: uint,
    claim-type: (string-ascii 32),
    bridge: (string-ascii 32),
    timestamp: uint,
    status: (string-ascii 16),
    evidence-hash: (buff 32)
  })
(define-map user-claim-history principal (list 10 uint))
(define-map batch-transactions 
  uint 
  {
    bridges: (list 10 (string-ascii 32)),
    amounts: (list 10 uint),
    timestamp: uint,
    status: (string-ascii 16),
    gas-saved: uint
  })
(define-map bridge-risk-scores (string-ascii 32) uint)

;; Read-only functions
(define-read-only (get-total-value-locked)
  (var-get total-value-locked))

(define-read-only (get-insurance-pool-balance)
  (var-get insurance-pool-balance))

(define-read-only (get-user-deposit (user principal))
  (default-to u0 (map-get? user-deposits user)))

(define-read-only (get-user-insurance-stake (user principal))
  (default-to u0 (map-get? user-insurance-stakes user)))

(define-read-only (get-user-bridge-shares (user principal))
  (default-to u0 (map-get? user-bridge-shares user)))

(define-read-only (get-bridge-allocation (bridge (string-ascii 32)))
  (map-get? bridge-allocations {bridge: bridge}))

(define-read-only (get-insurance-claim (claim-id uint))
  (map-get? insurance-claims claim-id))

(define-read-only (get-user-estimated-peg-value (user principal))
  (let ((user-shares (get-user-bridge-shares user))
        (total-shares (var-get total-value-locked)))
    (if (> total-shares u0)
        (/ (* user-shares (calculate-total-peg-ratio)) u10000)
        u0)))

(define-read-only (calculate-total-peg-ratio)
  (fold calculate-weighted-peg (list 
    "wrapped-bitcoin" "alex-xbtc" "arkadiko-xbtc" "stackswap-xbtc" "bitflow-xbtc" 
    "velar-xbtc" "zest-xbtc" "hermetica-xbtc" "trustless-btc" "lightning-btc") u0))

(define-read-only (get-bridge-risk-score (bridge (string-ascii 32)))
  (default-to u500 (map-get? bridge-risk-scores bridge))) ;; Default 50% risk score

(define-read-only (get-optimal-allocation)
  (let ((bridges (list "wrapped-bitcoin" "alex-xbtc" "arkadiko-xbtc" "stackswap-xbtc" "bitflow-xbtc")))
    (map get-bridge-metrics bridges)))

;; Private functions
(define-private (calculate-weighted-peg (bridge (string-ascii 32)) (acc uint))
  (match (get-bridge-allocation bridge)
    allocation (+ acc (/ (* (get allocation-percentage allocation) (get peg-ratio allocation)) u100))
    acc))

(define-private (get-bridge-metrics (bridge (string-ascii 32)))
  {
    bridge: bridge,
    peg-ratio: (default-to u0 (get peg-ratio (get-bridge-allocation bridge))),
    risk-score: (get-bridge-risk-score bridge),
    allocation: (default-to u0 (get allocation-percentage (get-bridge-allocation bridge)))
  })

(define-private (validate-bridge (bridge (string-ascii 32)))
  (or (is-eq bridge "wrapped-bitcoin")
      (or (is-eq bridge "alex-xbtc")
          (or (is-eq bridge "arkadiko-xbtc")
              (or (is-eq bridge "stackswap-xbtc")
                  (or (is-eq bridge "bitflow-xbtc")
                      (or (is-eq bridge "velar-xbtc")
                          (or (is-eq bridge "zest-xbtc")
                              (or (is-eq bridge "hermetica-xbtc")
                                  (or (is-eq bridge "trustless-btc")
                                      (is-eq bridge "lightning-btc")))))))))))

(define-private (calculate-insurance-premium (amount uint) (bridge (string-ascii 32)))
  (let ((risk-score (get-bridge-risk-score bridge)))
    (/ (* amount risk-score) u10000)))

(define-private (update-bridge-allocation (bridge (string-ascii 32)) (new-allocation uint))
  (begin
    (asserts! (validate-bridge bridge) ERR_INVALID_BRIDGE)
    (match (get-bridge-allocation bridge)
      current-data (map-set bridge-allocations 
        {bridge: bridge}
        (merge current-data {allocation-percentage: new-allocation}))
      (map-set bridge-allocations 
        {bridge: bridge}
        {allocation-percentage: new-allocation, last-sync: block-height, total-bridged: u0, peg-ratio: u0}))
    (ok true)))

;; Public functions

;; Bridge Functions
(define-public (deposit-for-bridging (amount uint))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (let ((current-deposit (get-user-deposit tx-sender))
          (current-shares (get-user-bridge-shares tx-sender))
          (new-shares (+ current-shares amount)))
      (map-set user-deposits tx-sender (+ current-deposit amount))
      (map-set user-bridge-shares tx-sender new-shares)
      (var-set total-value-locked (+ (var-get total-value-locked) amount))
      (try! (auto-rebalance-bridges))
      (ok new-shares))))

(define-public (withdraw-bridged (amount uint))
  (let ((user-deposit (get-user-deposit tx-sender))
        (user-shares (get-user-bridge-shares tx-sender)))
    (asserts! (>= user-shares amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    (map-set user-deposits tx-sender (- user-deposit amount))
    (map-set user-bridge-shares tx-sender (- user-shares amount))
    (var-set total-value-locked (- (var-get total-value-locked) amount))
    (ok amount)))

(define-public (sync-bridge-pegs (bridges (list 10 (string-ascii 32))))
  (begin
    (asserts! (<= (len bridges) (var-get max-batch-size)) ERR_BATCH_LIMIT_EXCEEDED)
    (let ((batch-id (+ (var-get batch-counter) u1))
          (gas-estimate (calculate-gas-savings bridges)))
      (var-set batch-counter batch-id)
      (map-set batch-transactions batch-id
        {
          bridges: bridges,
          amounts: (map get-bridge-amount bridges),
          timestamp: block-height,
          status: "processing",
          gas-saved: gas-estimate
        })
      (try! (process-sync-batch bridges))
      (map-set batch-transactions batch-id
        (merge (unwrap-panic (map-get? batch-transactions batch-id)) {status: "completed"}))
      (ok batch-id))))

(define-public (auto-rebalance-bridges)
  (let ((total-balance (var-get total-value-locked)))
    (if (> total-balance u0)
        (begin
          ;; Rebalance based on peg ratios and risk scores
          (try! (update-bridge-allocation "wrapped-bitcoin" u20))
          (try! (update-bridge-allocation "alex-xbtc" u15))
          (try! (update-bridge-allocation "arkadiko-xbtc" u25))
          (try! (update-bridge-allocation "stackswap-xbtc" u20))
          (try! (update-bridge-allocation "bitflow-xbtc" u20))
          (ok true))
        (ok false))))

;; Insurance Functions
(define-public (stake-for-insurance (amount uint))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (let ((current-stake (get-user-insurance-stake tx-sender)))
      (map-set user-insurance-stakes tx-sender (+ current-stake amount))
      (var-set insurance-pool-balance (+ (var-get insurance-pool-balance) amount))
      (ok (+ current-stake amount)))))

(define-public (unstake-insurance (amount uint))
  (let ((user-stake (get-user-insurance-stake tx-sender)))
    (asserts! (>= user-stake amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    (map-set user-insurance-stakes tx-sender (- user-stake amount))
    (var-set insurance-pool-balance (- (var-get insurance-pool-balance) amount))
    (ok amount)))

(define-public (file-insurance-claim (amount uint) (claim-type (string-ascii 32)) (bridge (string-ascii 32)) (evidence-hash (buff 32)))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (validate-bridge bridge) ERR_INVALID_BRIDGE)
    (asserts! (<= amount (var-get insurance-pool-balance)) ERR_INSUFFICIENT_COVERAGE)
    (let ((claim-id (+ (var-get claim-counter) u1))
          (premium (calculate-insurance-premium amount bridge)))
      (var-set claim-counter claim-id)
      (map-set insurance-claims claim-id
        {
          claimant: tx-sender,
          amount: amount,
          claim-type: claim-type,
          bridge: bridge,
          timestamp: block-height,
          status: "pending",
          evidence-hash: evidence-hash
        })
      ;; Update user claim history
      (let ((current-history (default-to (list) (map-get? user-claim-history tx-sender))))
        (map-set user-claim-history tx-sender (unwrap-panic (as-max-len? (append current-history claim-id) u10))))
      (ok claim-id))))

(define-public (process-insurance-claim (claim-id uint) (approved bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (match (get-insurance-claim claim-id)
      claim-data
      (begin
        (asserts! (is-eq (get status claim-data) "pending") ERR_CLAIM_ALREADY_PROCESSED)
        (asserts! (< (- block-height (get timestamp claim-data)) (var-get claim-period)) ERR_CLAIM_EXPIRED)
        (if approved
            (begin
              (try! (as-contract (stx-transfer? (get amount claim-data) tx-sender (get claimant claim-data))))
              (var-set insurance-pool-balance (- (var-get insurance-pool-balance) (get amount claim-data)))
              (map-set insurance-claims claim-id (merge claim-data {status: "approved"}))
              (ok "claim-approved"))
            (begin
              (map-set insurance-claims claim-id (merge claim-data {status: "rejected"}))
              (ok "claim-rejected"))))
      ERR_CLAIM_NOT_FOUND)))

;; Utility Functions
(define-public (update-bridge-peg-ratio (bridge (string-ascii 32)) (new-ratio uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (validate-bridge bridge) ERR_INVALID_BRIDGE)
    (match (get-bridge-allocation bridge)
      current-data (begin
        (map-set bridge-allocations {bridge: bridge} 
          (merge current-data {peg-ratio: new-ratio}))
        (ok true))
      (begin
        (map-set bridge-allocations {bridge: bridge}
          {allocation-percentage: u0, last-sync: block-height, total-bridged: u0, peg-ratio: new-ratio})
        (ok true)))))

(define-public (update-bridge-risk-score (bridge (string-ascii 32)) (risk-score uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (validate-bridge bridge) ERR_INVALID_BRIDGE)
    (asserts! (<= risk-score u1000) ERR_INVALID_AMOUNT) ;; Max 100% risk
    (map-set bridge-risk-scores bridge risk-score)
    (ok true)))

(define-public (emergency-pause)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    ;; Emergency pause functionality would be implemented here
    (ok true)))

;; Helper functions for batch processing
(define-private (get-bridge-amount (bridge (string-ascii 32)))
  (match (get-bridge-allocation bridge)
    allocation (get total-bridged allocation)
    u0))

(define-private (calculate-gas-savings (bridges (list 10 (string-ascii 32))))
  ;; Simplified gas calculation - in practice this would be more complex
  (* (len bridges) u1000))

(define-private (process-sync-batch (bridges (list 10 (string-ascii 32))))
  (begin
    (asserts! (> (len bridges) u0) ERR_INVALID_AMOUNT)
    ;; This would interact with bridge protocols to sync peg ratios
    ;; For this example, we'll simulate the process
    (ok (fold process-single-sync bridges u0))))

(define-private (process-single-sync (bridge (string-ascii 32)) (acc uint))
  (match (get-bridge-allocation bridge)
    allocation (begin
      (map-set bridge-allocations {bridge: bridge}
        (merge allocation {last-sync: block-height}))
      (+ acc u1))
    acc))

;; Initialize default bridge risk scores
(map-set bridge-risk-scores "wrapped-bitcoin" u150)   
(map-set bridge-risk-scores "alex-xbtc" u200)         
(map-set bridge-risk-scores "arkadiko-xbtc" u180)     
(map-set bridge-risk-scores "stackswap-xbtc" u250)    
(map-set bridge-risk-scores "bitflow-xbtc" u220)     
(map-set bridge-risk-scores "velar-xbtc" u300)      
(map-set bridge-risk-scores "zest-xbtc" u280)       
(map-set bridge-risk-scores "hermetica-xbtc" u350)    
(map-set bridge-risk-scores "trustless-btc" u400)     
(map-set bridge-risk-scores "lightning-btc" u450)     