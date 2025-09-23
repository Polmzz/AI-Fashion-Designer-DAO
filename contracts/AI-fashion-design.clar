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
(define-constant err-not-winner (err u110))
(define-constant err-invalid-royalty-split (err u111))
(define-constant err-max-remix-depth (err u112))
(define-constant err-self-remix (err u113))

(define-data-var design-counter uint u0)
(define-data-var collection-counter uint u0)
(define-data-var voting-duration uint u1008)
(define-data-var min-stake uint u1000000)
(define-data-var dao-fee uint u100)
(define-data-var remix-counter uint u0)
(define-data-var remix-royalty-percentage uint u1500)
(define-data-var max-remix-depth uint u3)
(define-data-var remix-min-stake uint u500000)

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
    collection-id: (optional uint),
    remixable: bool,
    remix-count: uint
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

(define-map remixes
  uint
  {
    remix-id: uint,
    original-design-id: uint,
    remixer: principal,
    title: (string-ascii 64),
    description: (string-ascii 256),
    metadata-uri: (string-ascii 512),
    remix-depth: uint,
    parent-chain: (list 3 uint),
    royalty-split: uint,
    created-at: uint,
    status: (string-ascii 16),
    total-earned: uint
  }
)

(define-map design-remixes
  uint
  {remix-count: uint, total-remix-royalties: uint}
)

(define-map remix-votes
  {remix-id: uint, voter: principal}
  {vote: bool, timestamp: uint}
)

(define-map remix-ratings
  uint
  {
    total-votes: uint,
    positive-votes: uint,
    quality-score: uint,
    approved: bool
  }
)

(define-map creator-remix-earnings
  {creator: principal, design-id: uint}
  {total-earned: uint, remixes-created: uint}
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
      collection-id: none,
      remixable: true,
      remix-count: u0
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

(define-private (get-design-chain (design-id uint) (depth uint))
  (let ((chain (list design-id)))
    (if (> depth u0)
      (match (map-get? designs design-id)
        design (if (get remixable design)
                 chain
                 chain)
        chain
      )
      chain
    )
  )
)

(define-private (calculate-remix-depth (original-id uint))
  (match (map-get? remixes original-id)
    remix (+ (get remix-depth remix) u1)
    u1
  )
)

(define-public (create-remix 
  (original-design-id uint)
  (title (string-ascii 64))
  (description (string-ascii 256))
  (metadata-uri (string-ascii 512))
  (royalty-split uint)
)
  (let (
    (design (unwrap! (map-get? designs original-design-id) err-not-found))
    (remix-id (+ (var-get remix-counter) u1))
    (current-height (unwrap-panic (get-stacks-block-info? time burn-block-height)))
    (stake (var-get remix-min-stake))
    (remix-depth (calculate-remix-depth original-design-id))
  )
    (asserts! (is-eq (get status design) "winner") err-not-winner)
    (asserts! (get remixable design) err-unauthorized)
    (asserts! (not (is-eq (get creator design) tx-sender)) err-self-remix)
    (asserts! (<= remix-depth (var-get max-remix-depth)) err-max-remix-depth)
    (asserts! (and (>= royalty-split u500) (<= royalty-split u5000)) err-invalid-royalty-split)
    (asserts! (>= (stx-get-balance tx-sender) stake) err-insufficient-funds)
    
    (try! (stx-transfer? stake tx-sender (as-contract tx-sender)))
    
    (let ((parent-chain (unwrap-panic (as-max-len? (get-design-chain original-design-id remix-depth) u3))))
      (map-set remixes remix-id {
        remix-id: remix-id,
        original-design-id: original-design-id,
        remixer: tx-sender,
        title: title,
        description: description,
        metadata-uri: metadata-uri,
        remix-depth: remix-depth,
        parent-chain: parent-chain,
        royalty-split: royalty-split,
        created-at: current-height,
        status: "pending",
        total-earned: u0
      })
    )
    
    (map-set remix-ratings remix-id {
      total-votes: u0,
      positive-votes: u0,
      quality-score: u0,
      approved: false
    })
    
    (map-set design-remixes original-design-id
      (match (map-get? design-remixes original-design-id)
        existing (merge existing {remix-count: (+ (get remix-count existing) u1)})
        {remix-count: u1, total-remix-royalties: u0}
      )
    )
    
    (map-set designs original-design-id
      (merge design {remix-count: (+ (get remix-count design) u1)})
    )
    
    (var-set remix-counter remix-id)
    (ok remix-id)
  )
)

(define-public (vote-on-remix (remix-id uint) (approve bool))
  (let (
    (remix (unwrap! (map-get? remixes remix-id) err-not-found))
    (rating (unwrap! (map-get? remix-ratings remix-id) err-not-found))
    (voter-key {remix-id: remix-id, voter: tx-sender})
    (current-height (unwrap-panic (get-stacks-block-info? time burn-block-height)))
  )
    (asserts! (is-eq (get status remix) "pending") err-voting-closed)
    (asserts! (is-none (map-get? remix-votes voter-key)) err-already-voted)
    
    (map-set remix-votes voter-key {
      vote: approve,
      timestamp: current-height
    })
    
    (let (
      (new-total (+ (get total-votes rating) u1))
      (new-positive (if approve (+ (get positive-votes rating) u1) (get positive-votes rating)))
      (quality-score (/ (* new-positive u100) new-total))
    )
      (map-set remix-ratings remix-id {
        total-votes: new-total,
        positive-votes: new-positive,
        quality-score: quality-score,
        approved: (>= quality-score u60)
      })
      
      (if (and (>= new-total u5) (>= quality-score u60))
        (map-set remixes remix-id (merge remix {status: "approved"}))
        (if (and (>= new-total u10) (< quality-score u40))
          (map-set remixes remix-id (merge remix {status: "rejected"}))
          true
        )
      )
    )
    
    (ok true)
  )
)

(define-public (distribute-remix-royalties (remix-id uint) (payment-amount uint))
  (let (
    (remix (unwrap! (map-get? remixes remix-id) err-not-found))
    (original-design (unwrap! (map-get? designs (get original-design-id remix)) err-not-found))
    (royalty-amount (/ (* payment-amount (get royalty-split remix)) u10000))
    (remixer-amount (- payment-amount royalty-amount))
  )
    (asserts! (is-eq (get status remix) "approved") err-unauthorized)
    (asserts! (is-eq tx-sender (get remixer remix)) err-unauthorized)
    (asserts! (>= (stx-get-balance tx-sender) payment-amount) err-insufficient-funds)
    
    (try! (stx-transfer? royalty-amount tx-sender (get creator original-design)))
    
    (map-set remixes remix-id
      (merge remix {total-earned: (+ (get total-earned remix) payment-amount)})
    )
    
    (map-set design-remixes (get original-design-id remix)
      (match (map-get? design-remixes (get original-design-id remix))
        existing (merge existing {total-remix-royalties: (+ (get total-remix-royalties existing) royalty-amount)})
        {remix-count: u0, total-remix-royalties: royalty-amount}
      )
    )
    
    (map-set creator-remix-earnings 
      {creator: (get creator original-design), design-id: (get original-design-id remix)}
      (match (map-get? creator-remix-earnings {creator: (get creator original-design), design-id: (get original-design-id remix)})
        existing (merge existing {total-earned: (+ (get total-earned existing) royalty-amount)})
        {total-earned: royalty-amount, remixes-created: u0}
      )
    )
    
    (ok {royalty-paid: royalty-amount, remixer-keeps: remixer-amount})
  )
)

(define-public (toggle-remix-permission (design-id uint))
  (let ((design (unwrap! (map-get? designs design-id) err-not-found)))
    (asserts! (is-eq (get creator design) tx-sender) err-unauthorized)
    (asserts! (is-eq (get status design) "winner") err-not-winner)
    
    (map-set designs design-id
      (merge design {remixable: (not (get remixable design))})
    )
    
    (ok (not (get remixable design)))
  )
)

(define-public (claim-remix-stake (remix-id uint))
  (let (
    (remix (unwrap! (map-get? remixes remix-id) err-not-found))
    (stake (var-get remix-min-stake))
  )
    (asserts! (is-eq (get remixer remix) tx-sender) err-unauthorized)
    (asserts! (or (is-eq (get status remix) "approved") (is-eq (get status remix) "rejected")) err-voting-closed)
    
    (try! (as-contract (stx-transfer? stake tx-sender tx-sender)))
    
    (ok stake)
  )
)

(define-public (set-remix-parameters 
  (new-royalty-percentage uint)
  (new-max-depth uint)
  (new-min-stake uint)
)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (and (>= new-royalty-percentage u500) (<= new-royalty-percentage u5000)) err-invalid-royalty-split)
    (asserts! (and (> new-max-depth u0) (<= new-max-depth u5)) err-invalid-input)
    (asserts! (> new-min-stake u0) err-invalid-input)
    
    (var-set remix-royalty-percentage new-royalty-percentage)
    (var-set max-remix-depth new-max-depth)
    (var-set remix-min-stake new-min-stake)
    
    (ok true)
  )
)

(define-read-only (get-remix (remix-id uint))
  (map-get? remixes remix-id)
)

(define-read-only (get-remix-rating (remix-id uint))
  (map-get? remix-ratings remix-id)
)

(define-read-only (get-design-remix-stats (design-id uint))
  (map-get? design-remixes design-id)
)

(define-read-only (get-creator-remix-earnings (creator principal) (design-id uint))
  (map-get? creator-remix-earnings {creator: creator, design-id: design-id})
)

(define-read-only (get-remix-vote (remix-id uint) (voter principal))
  (map-get? remix-votes {remix-id: remix-id, voter: voter})
)

(define-read-only (get-remix-counter)
  (var-get remix-counter)
)

(define-read-only (get-remix-parameters)
  {
    royalty-percentage: (var-get remix-royalty-percentage),
    max-depth: (var-get max-remix-depth),
    min-stake: (var-get remix-min-stake)
  }
)

(define-read-only (can-remix (design-id uint))
  (match (map-get? designs design-id)
    design (and 
             (is-eq (get status design) "winner")
             (get remixable design))
    false
  )
)
