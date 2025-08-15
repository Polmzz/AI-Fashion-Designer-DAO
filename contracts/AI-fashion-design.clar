(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-voted (err u102))
(define-constant err-voting-closed (err u103))
(define-constant err-insufficient-funds (err u104))
(define-constant err-unauthorized (err u105))
(define-constant err-invalid-input (err u106))
(define-constant err-collection-not-found (err u107))
(define-constant err-collection-full (err u108))
(define-constant err-design-already-in-collection (err u109))

(define-data-var design-counter uint u0)
(define-data-var collection-counter uint u0)
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
    royalty-claimed: bool,
    collection-id: (optional uint)
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

(define-map collections
  uint
  {
    creator: principal,
    title: (string-ascii 64),
    description: (string-ascii 256),
    design-count: uint,
    max-designs: uint,
    created-at: uint,
    status: (string-ascii 16)
  }
)

(define-map collection-designs
  {collection-id: uint, design-id: uint}
  bool
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
      royalty-claimed: false,
      collection-id: none
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

(define-public (create-collection (title (string-ascii 64)) (description (string-ascii 256)) (max-designs uint))
  (let (
    (collection-id (+ (var-get collection-counter) u1))
    (current-height (unwrap-panic (get-stacks-block-info? time burn-block-height)))
  )
    (asserts! (> (len title) u0) err-invalid-input)
    (asserts! (> (len description) u0) err-invalid-input)
    (asserts! (and (> max-designs u0) (<= max-designs u20)) err-invalid-input)
    
    (map-set collections collection-id {
      creator: tx-sender,
      title: title,
      description: description,
      design-count: u0,
      max-designs: max-designs,
      created-at: current-height,
      status: "active"
    })
    
    (var-set collection-counter collection-id)
    (ok collection-id)
  )
)

(define-public (add-design-to-collection (design-id uint) (collection-id uint))
  (let (
    (design (unwrap! (map-get? designs design-id) err-not-found))
    (collection (unwrap! (map-get? collections collection-id) err-collection-not-found))
    (design-key {collection-id: collection-id, design-id: design-id})
  )
    (asserts! (is-eq (get creator design) tx-sender) err-unauthorized)
    (asserts! (is-eq (get creator collection) tx-sender) err-unauthorized)
    (asserts! (is-none (get collection-id design)) err-design-already-in-collection)
    (asserts! (< (get design-count collection) (get max-designs collection)) err-collection-full)
    (asserts! (is-eq (get status collection) "active") err-voting-closed)
    (asserts! (is-none (map-get? collection-designs design-key)) err-design-already-in-collection)
    
    (map-set designs design-id
      (merge design {collection-id: (some collection-id)})
    )
    
    (map-set collection-designs design-key true)
    
    (map-set collections collection-id
      (merge collection {design-count: (+ (get design-count collection) u1)})
    )
    
    (ok true)
  )
)

(define-public (vote-on-collection (collection-id uint) (vote-for bool) (vote-amount uint))
  (let (
    (collection (unwrap! (map-get? collections collection-id) err-collection-not-found))
    (vote-per-design (/ vote-amount (get design-count collection)))
    (design-count (get design-count collection))
  )
    (asserts! (is-eq (get status collection) "active") err-voting-closed)
    (asserts! (> vote-amount u0) err-invalid-input)
    (asserts! (>= (stx-get-balance tx-sender) vote-amount) err-insufficient-funds)
    (asserts! (> design-count u0) err-invalid-input)
    
    (try! (stx-transfer? vote-amount tx-sender (as-contract tx-sender)))
    
    (let (
      (current-id u1)
      (max-id (var-get design-counter))
    )
      (ok (fold process-design-vote
                (unwrap-panic (as-max-len? (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19 u20) u20))
                {collection-id: collection-id, vote-for: vote-for, vote-amount: vote-per-design, current-id: u1, max-id: max-id, designs-updated: u0}))
    )
  )
)

(define-private (process-design-vote (index uint) (context {collection-id: uint, vote-for: bool, vote-amount: uint, current-id: uint, max-id: uint, designs-updated: uint}))
  (let (
    (current-id (get current-id context))
    (max-id (get max-id context))
    (collection-id (get collection-id context))
    (vote-for (get vote-for context))
    (vote-amount (get vote-amount context))
    (designs-updated (get designs-updated context))
  )
    (if (and (<= current-id max-id) (< designs-updated u20))
      (let (
        (design-key {collection-id: collection-id, design-id: current-id})
      )
        (if (is-some (map-get? collection-designs design-key))
          (begin
            (match (map-get? designs current-id)
              design (begin
                (map-set designs current-id
                  (merge design {
                    total-votes: (+ (get total-votes design) u1),
                    votes-for: (if vote-for (+ (get votes-for design) u1) (get votes-for design)),
                    votes-against: (if vote-for (get votes-against design) (+ (get votes-against design) u1))
                  })
                )
                (match (map-get? royalty-pools current-id)
                  pool (map-set royalty-pools current-id
                         (merge pool {total-pool: (+ (get total-pool pool) vote-amount)}))
                  true
                )
              )
              true
            )
            (merge context {current-id: (+ current-id u1), designs-updated: (+ designs-updated u1)})
          )
          (merge context {current-id: (+ current-id u1)})
        )
      )
      context
    )
  )
)

(define-read-only (get-collection (collection-id uint))
  (map-get? collections collection-id)
)

(define-read-only (is-design-in-collection (design-id uint) (collection-id uint))
  (is-some (map-get? collection-designs {collection-id: collection-id, design-id: design-id}))
)

(define-read-only (get-collection-counter)
  (var-get collection-counter)
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
