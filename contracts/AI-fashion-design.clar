(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-voted (err u102))
(define-constant err-voting-closed (err u103))
(define-constant err-insufficient-funds (err u104))
(define-constant err-unauthorized (err u105))
(define-constant err-invalid-input (err u106))

(define-data-var design-counter uint u0)
(define-data-var voting-duration uint u1008)
(define-data-var min-stake uint u1000000)
(define-data-var dao-fee uint u100)

(define-map designs
  uint
  {
    creator: principal,
    title: (string-ascii 64),
    description: (string-ascii 256),
    metadata-uri: (string-ascii 512),
    stake-amount: uint,
    total-votes: uint,
    votes-for: uint,
    votes-against: uint,
    created-at: uint,
    voting-ends-at: uint,
    status: (string-ascii 16),
    royalty-claimed: bool
  }
)

(define-map votes
  {voter: principal, design-id: uint}
  {vote: bool, amount: uint, timestamp: uint}
)

(define-map user-stats
  principal
  {
    designs-created: uint,
    total-votes-cast: uint,
    total-royalties-earned: uint,
    reputation-score: uint
  }
)

(define-map royalty-pools
  uint
  {total-pool: uint, claimed: uint, per-vote-reward: uint}
)

(define-public (submit-design (title (string-ascii 64)) (description (string-ascii 256)) (metadata-uri (string-ascii 512)))
  (let (
    (design-id (+ (var-get design-counter) u1))
    (current-height (unwrap-panic (get-stacks-block-info? time burn-block-height)))
    (stake (var-get min-stake))
  )
    (asserts! (> (len title) u0) err-invalid-input)
    (asserts! (> (len description) u0) err-invalid-input)
    (asserts! (> (len metadata-uri) u0) err-invalid-input)
    (asserts! (>= (stx-get-balance tx-sender) stake) err-insufficient-funds)
    
    (try! (stx-transfer? stake tx-sender (as-contract tx-sender)))
    
    (map-set designs design-id {
      creator: tx-sender,
      title: title,
      description: description,
      metadata-uri: metadata-uri,
      stake-amount: stake,
      total-votes: u0,
      votes-for: u0,
      votes-against: u0,
      created-at: current-height,
      voting-ends-at: (+ current-height (var-get voting-duration)),
      status: "active",
      royalty-claimed: false
    })
    
    (map-set royalty-pools design-id {
      total-pool: u0,
      claimed: u0,
      per-vote-reward: u0
    })
    
    (map-set user-stats tx-sender
      (merge 
        (default-to {designs-created: u0, total-votes-cast: u0, total-royalties-earned: u0, reputation-score: u0}
                   (map-get? user-stats tx-sender))
        {designs-created: (+ (get designs-created (default-to {designs-created: u0, total-votes-cast: u0, total-royalties-earned: u0, reputation-score: u0} (map-get? user-stats tx-sender))) u1)}
      )
    )
    
    (var-set design-counter design-id)
    (ok design-id)
  )
)

(define-public (vote-on-design (design-id uint) (vote-for bool) (vote-amount uint))
  (let (
    (design (unwrap! (map-get? designs design-id) err-not-found))
    (current-height (unwrap-panic (get-stacks-block-info? time burn-block-height)))
    (voter-key {voter: tx-sender, design-id: design-id})
  )
    (asserts! (is-none (map-get? votes voter-key)) err-already-voted)
    (asserts! (<= current-height (get voting-ends-at design)) err-voting-closed)
    (asserts! (is-eq (get status design) "active") err-voting-closed)
    (asserts! (> vote-amount u0) err-invalid-input)
    (asserts! (>= (stx-get-balance tx-sender) vote-amount) err-insufficient-funds)
    
    (try! (stx-transfer? vote-amount tx-sender (as-contract tx-sender)))
    
    (map-set votes voter-key {
      vote: vote-for,
      amount: vote-amount,
      timestamp: current-height
    })
    
    (map-set designs design-id
      (merge design {
        total-votes: (+ (get total-votes design) u1),
        votes-for: (if vote-for (+ (get votes-for design) u1) (get votes-for design)),
        votes-against: (if vote-for (get votes-against design) (+ (get votes-against design) u1))
      })
    )
    
    (let ((pool (unwrap! (map-get? royalty-pools design-id) err-not-found)))
      (map-set royalty-pools design-id
        (merge pool {total-pool: (+ (get total-pool pool) vote-amount)})
      )
    )
    
    (map-set user-stats tx-sender
      (merge 
        (default-to {designs-created: u0, total-votes-cast: u0, total-royalties-earned: u0, reputation-score: u0}
                   (map-get? user-stats tx-sender))
        {total-votes-cast: (+ (get total-votes-cast (default-to {designs-created: u0, total-votes-cast: u0, total-royalties-earned: u0, reputation-score: u0} (map-get? user-stats tx-sender))) u1)}
      )
    )
    
    (ok true)
  )
)

(define-public (finalize-voting (design-id uint))
  (let (
    (design (unwrap! (map-get? designs design-id) err-not-found))
    (current-height (unwrap-panic (get-stacks-block-info? time burn-block-height)))
    (pool (unwrap! (map-get? royalty-pools design-id) err-not-found))
  )
    (asserts! (> current-height (get voting-ends-at design)) err-voting-closed)
    (asserts! (is-eq (get status design) "active") err-voting-closed)
    
    (let (
      (is-winner (> (get votes-for design) (get votes-against design)))
      (new-status (if is-winner "winner" "rejected"))
      (dao-cut (/ (* (get total-pool pool) (var-get dao-fee)) u10000))
      (creator-pool (- (get total-pool pool) dao-cut))
    )
      (map-set designs design-id
        (merge design {status: new-status})
      )
      
      (if is-winner
        (begin
          (map-set royalty-pools design-id
            (merge pool {per-vote-reward: (if (> (get votes-for design) u0) (/ creator-pool (get votes-for design)) u0)})
          )
          (map-set user-stats (get creator design)
            (merge 
              (default-to {designs-created: u0, total-votes-cast: u0, total-royalties-earned: u0, reputation-score: u0}
                         (map-get? user-stats (get creator design)))
              {reputation-score: (+ (get reputation-score (default-to {designs-created: u0, total-votes-cast: u0, total-royalties-earned: u0, reputation-score: u0} (map-get? user-stats (get creator design)))) u10)}
            )
          )
        )
        true
      )
      
      (ok new-status)
    )
  )
)

(define-public (claim-royalties (design-id uint))
  (let (
    (design (unwrap! (map-get? designs design-id) err-not-found))
    (voter-key {voter: tx-sender, design-id: design-id})
    (vote-data (unwrap! (map-get? votes voter-key) err-unauthorized))
    (pool (unwrap! (map-get? royalty-pools design-id) err-not-found))
  )
    (asserts! (is-eq (get status design) "winner") err-unauthorized)
    (asserts! (is-eq (get vote vote-data) true) err-unauthorized)
    (asserts! (> (get per-vote-reward pool) u0) err-insufficient-funds)
    
    (let ((reward (get per-vote-reward pool)))
      (try! (as-contract (stx-transfer? reward tx-sender tx-sender)))
      
      (map-delete votes voter-key)
      
      (map-set user-stats tx-sender
        (merge 
          (default-to {designs-created: u0, total-votes-cast: u0, total-royalties-earned: u0, reputation-score: u0}
                     (map-get? user-stats tx-sender))
          {total-royalties-earned: (+ (get total-royalties-earned (default-to {designs-created: u0, total-votes-cast: u0, total-royalties-earned: u0, reputation-score: u0} (map-get? user-stats tx-sender))) reward)}
        )
      )
      
      (ok reward)
    )
  )
)

(define-public (claim-creator-stake (design-id uint))
  (let (
    (design (unwrap! (map-get? designs design-id) err-not-found))
  )
    (asserts! (is-eq (get creator design) tx-sender) err-unauthorized)
    (asserts! (or (is-eq (get status design) "winner") (is-eq (get status design) "rejected")) err-voting-closed)
    (asserts! (is-eq (get royalty-claimed design) false) err-unauthorized)
    
    (map-set designs design-id
      (merge design {royalty-claimed: true})
    )
    
    (try! (as-contract (stx-transfer? (get stake-amount design) tx-sender tx-sender)))
    
    (ok (get stake-amount design))
  )
)

(define-public (update-voting-duration (new-duration uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> new-duration u0) err-invalid-input)
    (var-set voting-duration new-duration)
    (ok true)
  )
)

(define-public (update-min-stake (new-stake uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> new-stake u0) err-invalid-input)
    (var-set min-stake new-stake)
    (ok true)
  )
)

(define-public (update-dao-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-fee u1000) err-invalid-input)
    (var-set dao-fee new-fee)
    (ok true)
  )
)

(define-read-only (get-design (design-id uint))
  (map-get? designs design-id)
)

(define-read-only (get-vote (voter principal) (design-id uint))
  (map-get? votes {voter: voter, design-id: design-id})
)

(define-read-only (get-user-stats (user principal))
  (map-get? user-stats user)
)

(define-read-only (get-royalty-pool (design-id uint))
  (map-get? royalty-pools design-id)
)

(define-read-only (get-design-counter)
  (var-get design-counter)
)

(define-read-only (get-voting-duration)
  (var-get voting-duration)
)

(define-read-only (get-min-stake)
  (var-get min-stake)
)

(define-read-only (get-dao-fee)
  (var-get dao-fee)
)

(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender))
)

(define-read-only (is-voting-active (design-id uint))
  (match (map-get? designs design-id)
    design (and 
             (is-eq (get status design) "active")
             (<= (unwrap-panic (get-stacks-block-info? time burn-block-height)) (get voting-ends-at design)))
    false
  )
)
