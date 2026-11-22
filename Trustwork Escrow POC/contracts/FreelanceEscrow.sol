// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract FreelanceEscrow {
    enum State { Created, Funded, Submitted, Approved, Disputed, Resolved }

    struct Milestone {
        string description;
        uint256 amount;
        string deliverableIPFSHash;
        State state;
    }

    address public client;
    address public freelancer;
    address public arbiter;
    uint256 public platformFeePercent = 2; // 2% vs Fiverr's 20%
    address public platformWallet;

    Milestone[] public milestones;

    event MilestoneFunded(uint256 indexed id, uint256 amount);
    event WorkSubmitted(uint256 indexed id, string ipfsHash);
    event MilestonePaid(uint256 indexed id, uint256 freelancerAmount, uint256 fee);
    event DisputeRaised(uint256 indexed id);
    event DisputeResolved(uint256 indexed id, uint256 clientShare, uint256 freelancerShare);

    constructor(address _freelancer, address _arbiter, address _platformWallet) {
        client = msg.sender;
        freelancer = _freelancer;
        arbiter = _arbiter;
        platformWallet = _platformWallet;
    }

    function addMilestone(string memory _desc, uint256 _amount) external {
        require(msg.sender == client, "Only client can add milestones");
        milestones.push(Milestone(_desc, _amount, "", State.Created));
    }

    function fundMilestone(uint256 _id) external payable {
        Milestone storage m = milestones[_id];
        require(msg.sender == client, "Only client can fund");
        require(m.state == State.Created, "Already funded");
        require(msg.value == m.amount, "Incorrect amount");

        m.state = State.Funded;
        emit MilestoneFunded(_id, msg.value);
    }

    function submitWork(uint256 _id, string memory _ipfsHash) external {
        Milestone storage m = milestones[_id];
        require(msg.sender == freelancer, "Only freelancer can submit");
        require(m.state == State.Funded, "Milestone not funded");

        m.deliverableIPFSHash = _ipfsHash;
        m.state = State.Submitted;
        emit WorkSubmitted(_id, _ipfsHash);
    }

    function approveAndPay(uint256 _id) external {
        Milestone storage m = milestones[_id];
        require(msg.sender == client, "Only client can approve");
        require(m.state == State.Submitted, "Work not submitted");

        // Checks-Effects-Interactions: update state BEFORE sending funds
        m.state = State.Approved;
        uint256 fee = (m.amount * platformFeePercent) / 100;
        uint256 payout = m.amount - fee;

        (bool feeSuccess, ) = payable(platformWallet).call{value: fee}("");
        require(feeSuccess, "Fee transfer failed");

        (bool payoutSuccess, ) = payable(freelancer).call{value: payout}("");
        require(payoutSuccess, "Freelancer payout failed");

        emit MilestonePaid(_id, payout, fee);
    }

    function raiseDispute(uint256 _id) external {
        Milestone storage m = milestones[_id];
        require(msg.sender == client || msg.sender == freelancer, "Unauthorized");
        require(m.state == State.Funded || m.state == State.Submitted, "Cannot dispute");

        m.state = State.Disputed;
        emit DisputeRaised(_id);
    }

    function resolveDispute(uint256 _id, uint256 _freelancerShare) external {
        Milestone storage m = milestones[_id];
        require(msg.sender == arbiter, "Only arbiter can resolve");
        require(m.state == State.Disputed, "Not disputed");
        require(_freelancerShare <= m.amount, "Invalid split");

        // Checks-Effects-Interactions: update state BEFORE sending funds
        m.state = State.Resolved;
        uint256 clientShare = m.amount - _freelancerShare;

        if (_freelancerShare > 0) {
            (bool fSuccess, ) = payable(freelancer).call{value: _freelancerShare}("");
            require(fSuccess, "Freelancer transfer failed");
        }
        if (clientShare > 0) {
            (bool cSuccess, ) = payable(client).call{value: clientShare}("");
            require(cSuccess, "Client refund failed");
        }

        emit DisputeResolved(_id, clientShare, _freelancerShare);
    }
}