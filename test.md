# Literature Review

## 1. Introduction

The design of secure, privacy-preserving communication systems sits at the intersection of distributed systems engineering, applied cryptography, and digital rights scholarship. As the global population has migrated the bulk of its sensitive data exchange to a small number of centralised platforms, the attack surface for mass surveillance, commercial profiling, and state-level compulsion has grown in proportion. The ReLink system, described in this report, is motivated by a recognition that privacy degradation is not an incidental by-product of modern software design but an architectural consequence of choices made at the infrastructure level — choices that can be reversed by deliberately applying privacy-by-design principles (Cavoukian, 2009).

This literature review surveys four interconnected bodies of research that collectively inform the design rationale for ReLink. First, it examines the evolution of file-sharing architectures from centralised cloud storage through federated models to fully decentralised peer-to-peer systems, and evaluates the distinct privacy trade-offs each model introduces. Second, it reviews the WebRTC protocol stack and the growing body of work applying its DataChannel primitive to privacy-preserving file transfer. Third, it surveys the literature on zero-knowledge and server-blind communication paradigms, with particular attention to blind rendezvous protocols as a class of privacy-preserving bootstrapping mechanisms. Finally, it examines academic work on metadata minimisation, ephemeral storage, and identifier elimination as technical and legal controls against user profiling and censorship.

The review identifies a consistent gap in existing systems: no surveyed tool simultaneously offers (a) a native, cross-platform user experience, (b) trivially self-hostable deployment, (c) a cryptographically blind relay server, (d) modern end-to-end encrypted transport via WebRTC, and (e) zero persistent user identifiers. ReLink is designed to occupy that intersection.

---

## 2. Centralised vs. Decentralised File-Sharing Architectures

### 2.1 The Dominance and Dangers of Centralised Cloud Storage

The contemporary file-sharing landscape is dominated by a model in which user data is uploaded to, stored by, and retrieved from servers owned by a small number of commercial operators. Services such as Dropbox, Google Drive, and WeTransfer exemplify this pattern: the user's files transit through infrastructure controlled by a third party, which retains both the capability and — under many legal jurisdictions — the obligation to disclose that content upon lawful demand. Schneier (2015) characterises this structural feature as the defining vulnerability of the modern internet: the aggregation of sensitive user data at a small number of high-value targets converts cloud storage providers into what he terms "data honeypots," simultaneously attractive to state intelligence agencies, criminal adversaries, and the commercial surveillance apparatus of the operators themselves.

The economic logic underlying this model has been theorised most comprehensively by Zuboff (2019) under the framework of surveillance capitalism. In Zuboff's account, centralised data aggregation is not incidental to the business models of dominant platform firms but constitutive of them: behavioural data extracted from user activity is the primary raw material from which prediction products are manufactured and sold. File-sharing activity, including the identity of correspondents, the timing of transfers, and the inferred content of transmitted documents, constitutes precisely the kind of behavioural signal that feeds this extraction logic. Centralised architectures thus carry a structural privacy cost that persists even in the absence of malicious intent on the part of the operator.

From a security engineering perspective, the threat model extends beyond commercial exploitation. The Snowden disclosures of 2013 provided documentary evidence that major cloud storage providers were subject to compelled participation in mass surveillance programmes, including PRISM, in ways that their public privacy policies did not acknowledge [CITATION NEEDED: Greenwald, G. (2014). *No Place to Hide*. Metropolitan Books]. Centralised systems present an irresistible single point of compulsion: a lawful-access demand directed at one entity can yield the communications of millions of users. This asymmetry between the effort required by the surveillance actor and the privacy harm visited upon users is a fundamental structural problem that architectural decentralisation is well-positioned to address.

### 2.2 Federation as a Partial Mitigation

Federated architectures — in which multiple independently operated servers communicate through a shared open protocol — offer a partial mitigation of the centralisation risk. Protocols such as XMPP (Saint-Andre, 2011) and Matrix (Hodgson et al., 2019) allow users to choose or operate their own server, distributing the aggregation surface and reducing the impact of any single compromise or compulsion order. The adoption of ActivityPub as a W3C standard for federated social communication has further legitimised this model.

However, federation does not eliminate the metadata problem; it displaces it. In the Matrix protocol, for example, room membership, event graphs, and server-to-server routing information are replicated across all participating homeservers, meaning that a user's social graph and communication patterns may be visible to an arbitrarily large number of server operators. Hassan et al. (2023) [CITATION NEEDED: verify exact citation — authors and venue] have demonstrated that this replication behaviour creates substantial metadata leakage, with room membership lists and message timestamps persisting across servers even after users believe they have deleted content. The trust model of federation therefore differs in degree but not in kind from that of fully centralised systems: users must trust a collection of server operators rather than a single one, but they retain no technical guarantee that any of those operators will honour their privacy preferences.

For file transfer specifically, federation introduces additional complexity without proportionate benefit: large binary payloads must still be routed through server infrastructure, limiting throughput and creating storage obligations on intermediate nodes. The architectural insight that motivates purely peer-to-peer approaches is that the payload itself should never touch the infrastructure responsible for coordination.

### 2.3 Peer-to-Peer Models and Their Limitations

Fully decentralised peer-to-peer systems remove the trusted intermediary from the data path entirely. The BitTorrent protocol (Cohen, 2003) demonstrated at scale that direct peer exchange could achieve throughput and resilience that centralised servers could not match, though its design prioritised efficiency and robustness over privacy; the IP addresses of all peers are disclosed to all other peers and to the tracker, creating a surveillance surface exploited extensively by copyright enforcement agencies [CITATION NEEDED: Piatek et al. (2008). *Do you know where your files have been?* HotNets]. The InterPlanetary File System (Benet, 2014) attempts to address content addressability and permanence but, by design, makes content globally discoverable once published — the opposite of the ephemeral, need-to-know model that privacy-preserving file transfer requires.

More relevant to ReLink's design space are purpose-built private file transfer tools. Magic Wormhole [CITATION NEEDED: Warner, B. — project documentation] addresses the usability problem of establishing a shared secret between two parties by generating short, human-transcribable code phrases, using the SPAKE2 password-authenticated key exchange protocol to bootstrap a strongly encrypted channel. OnionShare (Lee, 2017) takes a different approach, running an ephemeral Tor onion service on the sender's machine to provide a high-anonymity transfer channel at the cost of substantially increased latency and a dependency on the Tor network being reachable. Both systems demonstrate the feasibility of server-minimal or server-free file transfer but each carries constraints — Magic Wormhole routes payload through a relay server it operates; OnionShare requires Tor and is therefore subject to the censorship and performance characteristics of the Tor network.

ReLink occupies a distinct position in this design space: it employs a minimal centralised rendezvous server strictly for the purpose of WebRTC signalling, after which the payload path is fully peer-to-peer and end-to-end encrypted. The relay server is architecturally incapable of reading either the content or the metadata of the transferred files, by cryptographic design rather than policy commitment.

---

## 3. WebRTC as a Substrate for Privacy-Preserving Peer-to-Peer Transfer

### 3.1 Protocol Origins and Security Architecture

Web Real-Time Communication (WebRTC) is a set of standards developed jointly by the W3C and the IETF RTCWEB working group, originally motivated by the need for browser-native voice and video communication without plugins (Jennings et al., 2013; RFC 8825). Its security architecture (RFC 8827) mandates that all media and data traffic be encrypted: the DTLS-SRTP framework ensures that a conformant WebRTC implementation cannot transmit payload in the clear under any operating condition. This is a qualitatively stronger guarantee than that offered by most application-layer encryption schemes, where encryption is a policy choice that can be misconfigured or deliberately circumvented. From a privacy engineering perspective, mandatory transport encryption means that even a compromised or malicious relay cannot observe the content of a DataChannel stream.

The DataChannel primitive (RFC 8831), built on SCTP multiplexed over DTLS, is particularly suited to file transfer: it supports reliable, ordered delivery (analogous to TCP semantics), large message fragmentation, and flow control, all over an encrypted peer-to-peer channel. The use of WebRTC DataChannels for file transfer has been explored in a number of prototypical systems, including ShareDrop, FilePizza, and similar browser-based tools [CITATION NEEDED: cite representative academic or technical survey of WebRTC file transfer tools], which collectively validate the feasibility of the approach at human-scale file sizes.

### 3.2 NAT Traversal and the Privacy Cost of TURN Relays

The primary practical obstacle to direct peer-to-peer connectivity is Network Address Translation (NAT), which is pervasive in consumer and enterprise networking and prevents arbitrary inbound connections to devices behind NAT gateways. The Interactive Connectivity Establishment (ICE) framework (RFC 8445) addresses this by systematically gathering candidate network paths — host addresses, server-reflexive addresses discovered via STUN, and relay addresses provided by TURN servers — and testing them in priority order to find a viable direct or relayed path between peers.

The privacy implications of ICE candidate gathering are non-trivial. Host candidates expose the device's local IP address; server-reflexive candidates expose its public IP address. Reiter and Rubin's (1998) anonymity framework, though predating WebRTC, provides a theoretical basis for understanding why IP address disclosure is a meaningful privacy harm: it permits network-level adversaries to link communication events to physical infrastructure and, by extension, to individual users. More recent work has demonstrated that browser-based WebRTC implementations could be abused to deanonymise users who were relying on VPNs, by leaking local IP addresses through ICE candidate gathering [CITATION NEEDED: Bonneau et al. or relevant WebRTC IP leak CVE documentation]. Chromium's subsequent adoption of mDNS-based candidate obfuscation — replacing local IP addresses with ephemeral `.local` hostnames in the ICE candidate list — mitigates this attack for browser implementations, though native implementations must apply equivalent care.

TURN relay servers, used as a fallback when direct connectivity fails, present the most significant privacy risk in the WebRTC stack: they observe the full payload of the data stream. This is architecturally equivalent to routing through a trusted third party and negates the privacy benefit of peer-to-peer connectivity if TURN is consistently required. ReLink's architecture accepts this trade-off: in network environments where direct connectivity is impossible, a TURN relay may be required and will observe encrypted (but opaque to it) DataChannel traffic. This is an acknowledged limitation and an area where future work — for example, the use of TURN over TLS with a server operated by neither peer — could reduce residual trust requirements.

### 3.3 Comparison with Alternative Transport Approaches

The alternative to WebRTC for encrypted peer-to-peer transfer would be a custom-built protocol using, for example, TLS mutual authentication over TCP or the QUIC transport protocol. Such an approach would avoid the complexity and the NAT-traversal privacy costs of ICE, but would forfeit the NAT traversal machinery itself — requiring either port forwarding, a relay server, or a transport-level hole-punching library, each of which introduces comparable or worse privacy trade-offs. WebRTC's ICE machinery represents decades of accumulated engineering for the specific problem of peer connectivity through NAT, and its mandatory encryption provides a stronger baseline guarantee than most application-layer TLS deployments, which are subject to misconfiguration. ReLink's choice of WebRTC DataChannels therefore reflects a deliberate balance between the engineering cost of NAT traversal, the strength of the transport security guarantee, and the maturity of the available implementation libraries.

---

## 4. Zero-Knowledge Signalling and Blind Rendezvous Protocols

### 4.1 Defining Server-Blind Operation

The term "zero-knowledge" in the cryptographic literature refers to a class of interactive proof systems in which a prover can convince a verifier of a statement's truth without disclosing any information beyond the validity of the statement itself (Goldwasser, Micali, & Rackoff, 1989). In the context of communication systems, the term is frequently used in a looser, operational sense to describe architectures in which the service operator is technically incapable of observing the content or metadata of user communications — a property more precisely characterised as *server-blind* or *operator-blind* operation. This review adopts the latter usage, distinguishing it from the strict cryptographic sense, and uses it to characterise systems in which the server's role is confined to routing or coordination without semantic access to the payload.

Server-blind signalling is a non-trivial engineering requirement. It demands that any shared secrets necessary for end-to-end encryption be established out-of-band — that is, through a channel that does not pass through the operator's infrastructure — and that the routing identifiers used by the server be meaningless without knowledge of those secrets.

### 4.2 Prior Art in Blind Rendezvous Design

The most directly relevant prior work is Magic Wormhole, an open-source tool that generates short, randomly selected code phrases and uses them as low-entropy inputs to the SPAKE2 password-authenticated key exchange protocol [CITATION NEEDED: Warner, B. — Magic Wormhole documentation and SPAKE2 RFC draft (draft-irtf-cfrg-spake2)]. The result is a protocol in which the relay server (the "mailbox server") stores encrypted blobs identified by the wormhole code, but cannot decrypt the content because it does not possess the shared password. This is architecturally close to ReLink's blind-mailbox pattern: both systems use a server-side store of short-lived opaque blobs identified by a code exchanged out-of-band. The principal differences are that Magic Wormhole uses SPAKE2 to derive the encryption key from the short code (tolerating some offline brute-force risk), whereas ReLink generates a cryptographically strong random token and transmits it out-of-band without performing a PAKE exchange; and that Magic Wormhole routes the file payload through its relay server as a fallback, whereas ReLink uses the server only for WebRTC signalling and transfers the payload entirely peer-to-peer.

OnionShare (Lee, 2017; Lee, 2021) achieves a stronger anonymity guarantee by instantiating the rendezvous point as a Tor onion service running on the sender's machine. Because the onion service address is ephemeral and bound to the sender's Tor identity key, no persistent identifier is created, and network-level observers cannot correlate the sender's IP address with the transfer activity. This approach places the rendezvous and transfer infrastructure under the sender's control, eliminating third-party trust entirely. The cost is substantial: the Tor network introduces latency of several hundred milliseconds to several seconds per round trip, severely limiting throughput for large file transfers, and the requirement that Tor be reachable makes OnionShare ineffective in environments where Tor is censored — precisely the environments where censorship resistance is most needed.

The Briar messaging system (Briar Project, n.d.) employs a Bramble Rendezvous Protocol (BRP) that uses shared secrets derived from a key agreement protocol to locate a contact's "mailbox" on an onion-service-based rendezvous server, without the server being able to link the mailbox identifier to the contact's network identity. Briar's model is closest to ReLink in terms of the threat model (server-blind, accountless, resistant to traffic analysis from the relay) but is designed for asynchronous messaging rather than file transfer, and its Tor dependency reintroduces the throughput and reachability concerns noted above.

In the academic literature on metadata-private messaging, the Vuvuzela system (van den Hooff et al., 2015) demonstrates the theoretical limit of what is achievable: even traffic analysis metadata can be concealed through differential privacy and cover traffic, at substantial throughput and latency cost. Alpenhorn (Lazar & Zeldovich, 2016) extends this model to the contact-discovery problem, showing how two parties can establish a shared communication channel without the server learning their identities or social graph. These systems are relevant as existence proofs that server-blind operation is not merely a policy aspiration but a technically achievable architectural property, though their overhead makes them unsuitable for large file transfer workloads.

Signal's Sealed Sender feature (Signal Foundation, 2018) provides a messaging-domain example of server-blind metadata: the server can deliver a message to its recipient without learning the sender's identity, because the sender identity is encrypted under the recipient's public key. This is a narrower form of server-blindness than ReLink implements — the Signal server still processes and stores messages, with awareness of recipient identities and timing — but it demonstrates the incremental adoption of server-blind design principles within a widely deployed production system.

### 4.3 Positioning ReLink's Contribution

Surveying this prior art, ReLink's rendezvous mechanism occupies a specific niche: a blind-mailbox pattern in which the server stores short-lived, opaque WebRTC signalling blobs (SDP offers, answers, and ICE candidates) indexed by a randomly generated mailbox identifier that has no semantic meaning to the server. The rendezvous token — used to locate the correct mailbox — is transmitted out-of-band and is never sent to the server in cleartext. This design is more usable than Tor-based approaches (no Tor dependency, near-native throughput), more self-hostable than Magic Wormhole's default relay (the entire stack is packaged as a Docker Compose deployment), and more strongly server-blind than federated approaches (the server cannot correlate mailbox identifiers across sessions or link them to user identities). The trade-off is that ReLink does not offer network-level anonymity: a passive network observer can determine that two IP addresses communicated with the signalling server in temporal proximity and subsequently established a WebRTC connection. This is an acknowledged and explicitly scoped limitation.

---

## 5. Metadata Minimisation, Ephemerality, and Resistance to Profiling

### 5.1 Metadata as the Primary Threat Vector

A recurring insight of both practitioner and academic work on surveillance is that metadata — the data *about* communications rather than their content — is frequently more revealing than content itself. This observation was given its starkest formulation by former NSA and CIA Director Michael Hayden, who stated publicly that "we kill people based on metadata" [CITATION NEEDED: Hayden, M. — Johns Hopkins Foreign Affairs Symposium, 2014], acknowledging that signals intelligence agencies use communication metadata for lethal targeting decisions without requiring access to message content.

The academic literature has substantiated this intuition empirically. Mayer, Mutchler, and Mitchell (2016) conducted a controlled study of telephone call metadata — records of who called whom, when, and for how long — and demonstrated that even a limited metadata record is sufficient to infer highly sensitive attributes including medical conditions, political affiliations, and personal relationships, without ever accessing the content of any communication. Their findings provide a rigorous empirical basis for the legal and engineering argument that content-focused encryption, while necessary, is insufficient as a privacy control: systems must also minimise the metadata they generate.

### 5.2 Privacy-by-Design and Legal Frameworks

The Privacy-by-Design framework (Cavoukian, 2009) argues that privacy protections should be embedded proactively in system architecture rather than retrofitted as compliance measures. Of its seven foundational principles, three are directly instantiated in ReLink's design: privacy as the default (no action is required from the user to avoid generating persistent identifiers — the system simply does not create them); end-to-end security (the WebRTC DataChannel encryption ensures that payload protection does not depend on the trustworthiness of any intermediary); and visibility and transparency (the open-source, self-hostable architecture allows any operator to verify that the system behaves as described).

The legal instantiation of the data minimisation principle is found in Article 5(1)(c) of the General Data Protection Regulation (GDPR), which requires that personal data be "adequate, relevant and limited to what is necessary in relation to the purposes for which they are processed." In the context of a file transfer service, the only data strictly necessary for the service's operation is a transient routing identifier for the signalling exchange; any additional data — user accounts, IP address logs, transfer histories — exceeds what is necessary and constitutes avoidable regulatory and privacy risk. ReLink's architecture is designed to collect nothing beyond what is operationally required for connection establishment, and to destroy even that immediately upon use.

### 5.3 Ephemeral Storage as a Technical Control

The concept of self-destructing or ephemeral data as a privacy control has been explored in the academic literature since at least the work of Geambasu et al. (2009), who proposed the Vanish system, in which data objects are encrypted under keys derived from distributed hash table nodes; as those nodes naturally churn and discard the key material, the encrypted data becomes permanently undecipherable, achieving a form of cryptographic self-destruction without requiring the user to take any action. Reardon, Basin, and Capkun (2013) provide a systematic treatment of secure data deletion across storage media and system layers, demonstrating that deletion is a technically difficult property to guarantee in complex systems with caching layers, journalling file systems, and backup infrastructure.

ReLink's approach to ephemerality is more pragmatic than cryptographic: signalling data is stored in a Redis instance configured as a pure in-memory cache with aggressive TTL values on all keys. This ensures that connection metadata is automatically purged on a short, bounded time horizon regardless of whether the connection succeeded or was abandoned. While this does not provide the cryptographic unrecoverability guarantees of Vanish, it is operationally sufficient for the threat model: the adversary most likely to demand server-side logs is a legal authority acting under compulsion, against which TTL-based deletion provides a technically credible "nothing to produce" response. Combined with the absence of persistent application-layer logs, this design ensures that the signalling server accumulates no durable record of who communicated with whom or when.

### 5.4 Identifier Elimination and Censorship Resistance

The elimination of persistent user identifiers is a design choice with implications for both privacy and censorship resistance. Accounts and registration requirements serve as leverage points for platform operators and external authorities: an account can be suspended, monitored, or used to correlate activity across time and network location. Systems that require registration — including many that present themselves as privacy-preserving, such as ProtonMail or Tresorit — can be compelled to block specific users, log specific accounts, or disclose registration metadata (email addresses, phone numbers, IP addresses at registration time) under legal process.

The "right to encryption" debate, crystallised in the *Keys Under Doormats* report (Abelson et al., 2015), has centred on whether states should have mandatory access to encryption keys. The report argues that any key escrow or backdoor requirement weakens security for all users and is technically unenforceable against adversaries who use non-compliant implementations. From the perspective of censorship resistance, the more tractable engineering response is to design systems in which there is simply no key to escrow and no account to suspend: if the server holds no secrets and no user records, compelled disclosure produces nothing of value. ReLink implements this principle — the signalling server has no user registry, stores no persistent state, and holds no cryptographic material relevant to the payload — making it an uninviting target for legal compulsion and technically incapable of complying with demands for user communication histories.

The self-hostable deployment model amplifies this resistance by eliminating the single point of compulsion. An operator under a censorship or takedown order cannot be compelled to deny service to users of other, independently deployed instances; and the low operational barrier to deploying a new instance (a single Docker Compose file and a domain name) means that suppressing the system in its entirety would require simultaneous action against every independent operator worldwide.

---

## 6. Synthesis and Identified Gap

The surveyed literature reveals a consistent trade-off space in which existing file transfer and communication tools make incompatible choices across five properties: (1) native, cross-platform user experience; (2) self-hostable deployment with low operational complexity; (3) server-blind operation — the relay is cryptographically incapable of observing content or metadata; (4) modern, mandatory end-to-end encrypted transport; and (5) zero persistent user identifiers.

Centralised cloud storage services (Dropbox, WeTransfer) optimise heavily for (1) and offer (4) in transit, but fail on (2), (3), and (5) by design. Federated systems (Matrix, XMPP) improve on (2) but replicate metadata across server nodes, undermining (3) and (5) in practice. BitTorrent achieves (4) in some configurations and partially (3) for payload, but exposes IP addresses and lacks (2) and (5). Magic Wormhole achieves a strong approximation of (3) and (5) but routes payload through a centrally operated relay, weakening (2) without eliminating it. OnionShare achieves (3) and (5) most robustly but sacrifices throughput and (1) through its Tor dependency, and its deployment model — running on the sender's machine — is not self-hostable in the traditional sense. Briar achieves the strongest combination of (3) and (5) for messaging but is not designed for large file transfer and shares OnionShare's Tor limitations.

No surveyed system achieves all five properties simultaneously. ReLink is designed to occupy this gap: a native cross-platform client (Flutter + Rust) provides (1); a Docker Compose deployment with a single configuration file provides (2); the blind-mailbox signalling architecture, in which the server stores only short-lived opaque blobs identified by tokens it cannot interpret, provides (3); mandatory WebRTC DTLS-SRTP encryption provides (4); and the accountless, identifier-free design provides (5). The acknowledged limitation — that ReLink does not provide network-level anonymity against a passive observer of signalling traffic — places it outside the threat model addressed by OnionShare and Briar, targeting instead the larger population of users who require operational privacy from the service operator and legal compulsion, but who do not face a nation-state network adversary with passive traffic analysis capability.

The remainder of this dissertation describes the detailed design, implementation, and evaluation of ReLink as a system that realises this architectural position.

---

## References

Abelson, H., Anderson, R., Bellovin, S. M., Benaloh, J., Blaze, M., Diffie, W., ... & Weitzner, D. (2015). *Keys Under Doormats: Mandating Insecurity by Requiring Government Access to All Data and Communications*. MIT Computer Science and Artificial Intelligence Laboratory Technical Report.

Benet, J. (2014). *IPFS — Content Addressed, Versioned, P2P File System*. arXiv:1407.3561.

Briar Project. (n.d.). *Bramble Rendezvous Protocol*. Retrieved from the Briar Project technical documentation.

Cavoukian, A. (2009). *Privacy by Design: The 7 Foundational Principles*. Information and Privacy Commissioner of Ontario.

Cohen, B. (2003). Incentives build robustness in BitTorrent. In *Proceedings of the Workshop on Economics of Peer-to-Peer Systems*, vol. 6, pp. 68–72.

Geambasu, R., Kohno, T., Levy, A., & Levy, H. M. (2009). Vanish: Increasing data privacy with self-destructing data. In *Proceedings of the 18th USENIX Security Symposium*, pp. 299–316.

Goldwasser, S., Micali, S., & Rackoff, C. (1989). The knowledge complexity of interactive proof systems. *SIAM Journal on Computing*, 18(1), 186–208.

Jennings, C., Hardie, T., & Westerlund, M. (Eds.). (2013). *Real-Time Communications for the Web*. RFC 8825. Internet Engineering Task Force.

Lazar, D., & Zeldovich, N. (2016). Alpenhorn: Bootstrapping secure communication without leaking metadata. In *Proceedings of the 12th USENIX Symposium on Operating Systems Design and Implementation (OSDI)*, pp. 571–586.

Lee, M. (2021). *OnionShare 2.0*. [CITATION NEEDED: verify full publication/documentation citation]

Mayer, J., Mutchler, P., & Mitchell, J. C. (2016). Evaluating the privacy properties of telephone metadata. *Proceedings of the National Academy of Sciences*, 113(20), 5536–5541.

Reardon, J., Basin, D., & Capkun, S. (2013). SoK: Secure data deletion. In *Proceedings of the 2013 IEEE Symposium on Security and Privacy*, pp. 301–315.

Reiter, M. K., & Rubin, A. D. (1998). Crowds: Anonymity for web transactions. *ACM Transactions on Information and System Security*, 1(1), 66–92.

RFC 8445. (2018). *Interactive Connectivity Establishment (ICE): A Protocol for Network Address Translator (NAT) Traversal*. Internet Engineering Task Force.

RFC 8827. (2021). *WebRTC Security Architecture*. Internet Engineering Task Force.

RFC 8831. (2021). *WebRTC Data Channels*. Internet Engineering Task Force.

Saint-Andre, P. (2011). *Extensible Messaging and Presence Protocol (XMPP): Core*. RFC 6120. Internet Engineering Task Force.

Schneier, B. (2015). *Data and Goliath: The Hidden Battles to Collect Your Data and Control Your World*. W. W. Norton & Company.

Signal Foundation. (2018). *Sealed Sender*. Signal Blog. [CITATION NEEDED: full URL or archived version]

van den Hooff, J., Lazar, D., Zaharia, M., & Zeldovich, N. (2015). Vuvuzela: Scalable private messaging resistant to traffic analysis. In *Proceedings of the 25th ACM Symposium on Operating Systems Principles (SOSP)*, pp. 137–152.

Warner, B. (n.d.). *Magic Wormhole*. [CITATION NEEDED: cite GitHub repository or associated technical write-up with date]

Zuboff, S. (2019). *The Age of Surveillance Capitalism: The Fight for a Human Future at the New Frontier of Power*. PublicAffairs.
