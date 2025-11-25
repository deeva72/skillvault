;; Skill Vault - Decentralized Professional Credential Platform
;; A secure, verifiable skill endorsement and certification system on Stacks

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-not-found (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-invalid-input (err u104))
(define-constant err-already-endorsed (err u105))
(define-constant err-self-endorse (err u106))
(define-constant err-expired (err u107))
(define-constant err-not-verified (err u108))
(define-constant err-invalid-level (err u109))
(define-constant err-insufficient-stake (err u110))
(define-constant err-already-challenged (err u111))
(define-constant err-challenge-period-ended (err u112))
(define-constant err-paused (err u113))

;; Minimum stake for endorsement: 1 STX
(define-constant min-endorsement-stake u1000000)

;; Challenge period: 144 blocks (~24 hours)
(define-constant challenge-period u144)

;; Data Variables
(define-data-var skill-nonce uint u0)
(define-data-var credential-nonce uint u0)
(define-data-var contract-paused bool false)
(define-data-var total-endorsements uint u0)
(define-data-var total-credentials-issued uint u0)

;; Data Maps
(define-map skills
    uint
    {
        name: (string-ascii 50),
        category: (string-ascii 30),
        description: (string-utf8 200),
        creator: principal,
        verified: bool,
        active: bool
    }
)

(define-map user-skills
    {user: principal, skill-id: uint}
    {
        level: uint,
        experience-years: uint,
        added-at: uint,
        verified: bool,
        total-endorsements: uint,
        stake-locked: uint
    }
)

(define-map endorsements
    {endorser: principal, user: principal, skill-id: uint}
    {
        endorsed-at: uint,
        stake: uint,
        active: bool,
        comment: (string-utf8 140)
    }
)

(define-map credentials
    uint
    {
        holder: principal,
        skill-id: uint,
        issuer: principal,
        issued-at: uint,
        expires-at: uint,
        credential-type: (string-ascii 20),
        metadata: (string-utf8 200),
        revoked: bool
    }
)

(define-map user-reputation
    principal
    {
        endorsements-given: uint,
        endorsements-received: uint,
        credentials-earned: uint,
        reputation-score: uint
    }
)

(define-map skill-experts
    {skill-id: uint, index: uint}
    principal
)

(define-map skill-expert-count
    uint
    uint
)

(define-map challenges
    {credential-id: uint, challenger: principal}
    {
        challenged-at: uint,
        stake: uint,
        reason: (string-utf8 200),
        resolved: bool,
        upheld: bool
    }
)

;; Read-only functions
(define-read-only (get-skill (skill-id uint))
    (map-get? skills skill-id)
)

(define-read-only (get-user-skill (user principal) (skill-id uint))
    (map-get? user-skills {user: user, skill-id: skill-id})
)

(define-read-only (get-endorsement (endorser principal) (user principal) (skill-id uint))
    (map-get? endorsements {endorser: endorser, user: user, skill-id: skill-id})
)

(define-read-only (get-credential (credential-id uint))
    (map-get? credentials credential-id)
)

(define-read-only (get-user-reputation (user principal))
    (default-to 
        {endorsements-given: u0, endorsements-received: u0, credentials-earned: u0, reputation-score: u0}
        (map-get? user-reputation user)
    )
)

(define-read-only (get-skill-expert-count (skill-id uint))
    (default-to u0 (map-get? skill-expert-count skill-id))
)

(define-read-only (get-skill-expert-at-index (skill-id uint) (index uint))
    (map-get? skill-experts {skill-id: skill-id, index: index})
)

(define-read-only (get-challenge (credential-id uint) (challenger principal))
    (map-get? challenges {credential-id: credential-id, challenger: challenger})
)

(define-read-only (is-paused)
    (var-get contract-paused)
)

(define-read-only (get-total-endorsements)
    (var-get total-endorsements)
)

(define-read-only (get-total-credentials-issued)
    (var-get total-credentials-issued)
)

(define-read-only (calculate-reputation-score (user principal))
    (let
        (
            (reputation (get-user-reputation user))
        )
        (+ 
            (* (get endorsements-received reputation) u10)
            (* (get credentials-earned reputation) u50)
            (* (get endorsements-given reputation) u5)
        )
    )
)

;; Private helper functions
(define-private (is-skill-holder (user principal) (skill-id uint))
    (is-some (map-get? user-skills {user: user, skill-id: skill-id}))
)

;; Public functions

;; Create a new skill category
(define-public (create-skill 
    (name (string-ascii 50))
    (category (string-ascii 30))
    (description (string-utf8 200))
)
    (let
        (
            (new-id (+ (var-get skill-nonce) u1))
        )
        (asserts! (not (var-get contract-paused)) err-paused)
        (asserts! (> (len name) u0) err-invalid-input)
        
        (map-set skills new-id
            {
                name: name,
                category: category,
                description: description,
                creator: tx-sender,
                verified: false,
                active: true
            }
        )
        
        (map-set skill-expert-count new-id u0)
        (var-set skill-nonce new-id)
        (ok new-id)
    )
)

;; Verify skill (owner only)
(define-public (verify-skill (skill-id uint))
    (let
        (
            (skill (unwrap! (map-get? skills skill-id) err-not-found))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        
        (map-set skills skill-id
            (merge skill {verified: true})
        )
        (ok true)
    )
)

;; Add skill to user profile
(define-public (add-skill-to-profile 
    (skill-id uint)
    (level uint)
    (experience-years uint)
)
    (let
        (
            (skill (unwrap! (map-get? skills skill-id) err-not-found))
        )
        (asserts! (not (var-get contract-paused)) err-paused)
        (asserts! (get active skill) err-not-found)
        (asserts! (and (>= level u1) (<= level u5)) err-invalid-level)
        (asserts! (not (is-skill-holder tx-sender skill-id)) err-already-exists)
        
        (map-set user-skills {user: tx-sender, skill-id: skill-id}
            {
                level: level,
                experience-years: experience-years,
                added-at: stacks-block-height,
                verified: false,
                total-endorsements: u0,
                stake-locked: u0
            }
        )
        
        (ok true)
    )
)

;; Endorse a user's skill (requires stake)
(define-public (endorse-skill 
    (user principal)
    (skill-id uint)
    (stake-amount uint)
    (comment (string-utf8 140))
)
    (let
        (
            (user-skill (unwrap! (map-get? user-skills {user: user, skill-id: skill-id}) err-not-found))
            (endorser-reputation (get-user-reputation tx-sender))
            (endorsed-user-reputation (get-user-reputation user))
        )
        (asserts! (not (var-get contract-paused)) err-paused)
        (asserts! (not (is-eq tx-sender user)) err-self-endorse)
        (asserts! (>= stake-amount min-endorsement-stake) err-insufficient-stake)
        (asserts! (is-none (map-get? endorsements {endorser: tx-sender, user: user, skill-id: skill-id})) err-already-endorsed)
        
        ;; Transfer stake to contract
        (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
        
        ;; Create endorsement
        (map-set endorsements {endorser: tx-sender, user: user, skill-id: skill-id}
            {
                endorsed-at: stacks-block-height,
                stake: stake-amount,
                active: true,
                comment: comment
            }
        )
        
        ;; Update user skill
        (map-set user-skills {user: user, skill-id: skill-id}
            (merge user-skill {
                total-endorsements: (+ (get total-endorsements user-skill) u1),
                stake-locked: (+ (get stake-locked user-skill) stake-amount)
            })
        )
        
        ;; Update reputations
        (map-set user-reputation tx-sender
            (merge endorser-reputation {
                endorsements-given: (+ (get endorsements-given endorser-reputation) u1),
                reputation-score: (calculate-reputation-score tx-sender)
            })
        )
        
        (map-set user-reputation user
            (merge endorsed-user-reputation {
                endorsements-received: (+ (get endorsements-received endorsed-user-reputation) u1),
                reputation-score: (calculate-reputation-score user)
            })
        )
        
        ;; Update global stats
        (var-set total-endorsements (+ (var-get total-endorsements) u1))
        
        ;; Add to experts list if enough endorsements
        (if (>= (get total-endorsements user-skill) u5)
            (let
                (
                    (current-count (get-skill-expert-count skill-id))
                )
                (map-set skill-experts {skill-id: skill-id, index: current-count} user)
                (map-set skill-expert-count skill-id (+ current-count u1))
                (ok true)
            )
            (ok true)
        )
    )
)

;; Issue credential (verified skill holders only)
(define-public (issue-credential
    (holder principal)
    (skill-id uint)
    (duration-blocks uint)
    (credential-type (string-ascii 20))
    (metadata (string-utf8 200))
)
    (let
        (
            (new-id (+ (var-get credential-nonce) u1))
            (issuer-skill (unwrap! (map-get? user-skills {user: tx-sender, skill-id: skill-id}) err-not-authorized))
            (holder-reputation (get-user-reputation holder))
        )
        (asserts! (not (var-get contract-paused)) err-paused)
        (asserts! (>= (get total-endorsements issuer-skill) u3) err-not-verified)
        (asserts! (> duration-blocks u0) err-invalid-input)
        
        (map-set credentials new-id
            {
                holder: holder,
                skill-id: skill-id,
                issuer: tx-sender,
                issued-at: stacks-block-height,
                expires-at: (+ stacks-block-height duration-blocks),
                credential-type: credential-type,
                metadata: metadata,
                revoked: false
            }
        )
        
        ;; Update holder reputation
        (map-set user-reputation holder
            (merge holder-reputation {
                credentials-earned: (+ (get credentials-earned holder-reputation) u1),
                reputation-score: (calculate-reputation-score holder)
            })
        )
        
        ;; Update global stats
        (var-set credential-nonce new-id)
        (var-set total-credentials-issued (+ (var-get total-credentials-issued) u1))
        
        (ok new-id)
    )
)

;; Challenge a credential (requires stake)
(define-public (challenge-credential
    (credential-id uint)
    (stake-amount uint)
    (reason (string-utf8 200))
)
    (let
        (
            (credential (unwrap! (map-get? credentials credential-id) err-not-found))
        )
        (asserts! (not (var-get contract-paused)) err-paused)
        (asserts! (not (get revoked credential)) err-not-found)
        (asserts! (< stacks-block-height (get expires-at credential)) err-expired)
        (asserts! (>= stake-amount min-endorsement-stake) err-insufficient-stake)
        (asserts! (is-none (map-get? challenges {credential-id: credential-id, challenger: tx-sender})) err-already-challenged)
        
        ;; Transfer challenge stake
        (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
        
        (map-set challenges {credential-id: credential-id, challenger: tx-sender}
            {
                challenged-at: stacks-block-height,
                stake: stake-amount,
                reason: reason,
                resolved: false,
                upheld: false
            }
        )
        
        (ok true)
    )
)

;; Resolve challenge (owner only)
(define-public (resolve-challenge
    (credential-id uint)
    (challenger principal)
    (upheld bool)
)
    (let
        (
            (challenge (unwrap! (map-get? challenges {credential-id: credential-id, challenger: challenger}) err-not-found))
            (credential (unwrap! (map-get? credentials credential-id) err-not-found))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (not (get resolved challenge)) err-already-challenged)
        
        (if upheld
            ;; Challenge upheld - revoke credential and return stake to challenger
            (begin
                (map-set credentials credential-id
                    (merge credential {revoked: true})
                )
                (try! (as-contract (stx-transfer? (get stake challenge) tx-sender challenger)))
                (ok true)
            )
            ;; Challenge rejected - return stake to credential issuer
            (begin
                (try! (as-contract (stx-transfer? (get stake challenge) tx-sender (get issuer credential))))
                (ok true)
            )
        )
    )
)

;; Revoke credential (issuer only)
(define-public (revoke-credential (credential-id uint))
    (let
        (
            (credential (unwrap! (map-get? credentials credential-id) err-not-found))
        )
        (asserts! (is-eq tx-sender (get issuer credential)) err-not-authorized)
        (asserts! (not (get revoked credential)) err-not-found)
        
        (map-set credentials credential-id
            (merge credential {revoked: true})
        )
        (ok true)
    )
)

;; Withdraw endorsement stake (after skill verification or time period)
(define-public (withdraw-endorsement-stake
    (user principal)
    (skill-id uint)
)
    (let
        (
            (endorsement (unwrap! (map-get? endorsements {endorser: tx-sender, user: user, skill-id: skill-id}) err-not-found))
            (user-skill (unwrap! (map-get? user-skills {user: user, skill-id: skill-id}) err-not-found))
        )
        (asserts! (get active endorsement) err-not-found)
        (asserts! (or 
            (get verified user-skill)
            (> stacks-block-height (+ (get endorsed-at endorsement) u4320))  ;; ~30 days
        ) err-invalid-input)
        
        ;; Return stake
        (try! (as-contract (stx-transfer? (get stake endorsement) tx-sender tx-sender)))
        
        ;; Deactivate endorsement
        (map-set endorsements {endorser: tx-sender, user: user, skill-id: skill-id}
            (merge endorsement {active: false})
        )
        
        ;; Update user skill stake
        (map-set user-skills {user: user, skill-id: skill-id}
            (merge user-skill {
                stake-locked: (- (get stake-locked user-skill) (get stake endorsement))
            })
        )
        
        (ok (get stake endorsement))
    )
)

;; Update skill level
(define-public (update-skill-level
    (skill-id uint)
    (new-level uint)
)
    (let
        (
            (user-skill (unwrap! (map-get? user-skills {user: tx-sender, skill-id: skill-id}) err-not-found))
        )
        (asserts! (and (>= new-level u1) (<= new-level u5)) err-invalid-level)
        (asserts! (>= (get total-endorsements user-skill) u2) err-not-verified)
        
        (map-set user-skills {user: tx-sender, skill-id: skill-id}
            (merge user-skill {level: new-level})
        )
        (ok true)
    )
)

;; Pause contract (owner only)
(define-public (pause-contract)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set contract-paused true)
        (ok true)
    )
)

;; Unpause contract (owner only)
(define-public (unpause-contract)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set contract-paused false)
        (ok true)
    )
)