pragma solidity ^0.4.11;

import "./SafeMath.sol";
import './Halt.sol';


contract HTLCBase is Halt {
    using SafeMath for uint;

    /**
    *
    * ENUMS
    *
    */

    /// @notice tx info status
    /// @notice uninitialized,locked,refunded,revoked
    enum TxStatus {None, Locked, Refunded, Revoked}

    /// @notice tx direction
    enum TxDirection {Coin2Wtoken, Wtoken2Coin}

    /**
    *
    * STRUCTURES
    *
    */

    /// @notice HTLC(Hashed TimeLock Contract) tx info
    struct HTLCTx {
        TxDirection direction;  // HTLC transfer direction
        address  source;        // HTLC transaction source address
        address  destination;   // HTLC transaction destination address
        uint value;             // HTLC transfer value of token
        TxStatus status;        // HTLC transaction status
        uint lockedTime;        // HTLC transaction locked time
        uint beginLockedTime;   // HTLC transaction begin locked time
    }


    /**
    *
    * VARIABLES
    *
    */

    /// @notice mapping of hash(x) to HTLCTx
    mapping(bytes32 => HTLCTx) public mapXHashHTLCTxs;

    /// @notice mapping of hash(x) to shadow address
    mapping(bytes32 => address) public mapXHashShadow;

    /// @notice atomic tx needed locked time(in seconds)
    uint public lockedTime;
    
    /// @notice default locked time(in seconds)
    uint public constant DEF_LOCKED_TIME = uint(3600*36);
    
    /// @notice default max UTC time
    uint public constant DEF_MAX_TIME = uint(0xffffffffffffffff);

    /// @notice the fee ratio of revoking operation
    uint public revokeFeeRatio;

    /// @notice revoking fee ratio precise
    /// @notice for example: revokeFeeRatio is 3, meaning that the revoking fee ratio is 3/10000
    uint public constant RATIO_PRECISE = 10000;


    /**
    *
    * MANIPULATIONS
    *
    */
    
    /// Constructor
    function HTLCBase()
        public
    {
        lockedTime = DEF_LOCKED_TIME;
    }

    /// @notice default transfer to contract
    function () 
        public
        payable 
    {
        revert();
    }

    /// @notice destruct SC and transfer balance to owner
    function kill()
        public
        onlyOwner
        isHalted
    {
        selfdestruct(owner);
    }

    /// @notice set locked time(only owner has the right)
    /// @param  time the locked time，in seconds
    function setLockedTime(uint time)
        public
        onlyOwner
        isHalted
        returns (bool)
    {
        lockedTime = time;
        return true;
    }

    /// @notice         get left locked time of the HTLC transaction
    /// @param  xHash   hash of HTLC random number
    /// @return time    return left locked time, in seconds. return uint(0xffffffffffffffff) if xHash does not exist
    function getHTLCLeftLockedTime(bytes32 xHash) 
        public 
        view 
        returns(uint time) 
    {
        HTLCTx storage info = mapXHashHTLCTxs[xHash];
        if (info.status == TxStatus.None) {
            return DEF_MAX_TIME;
        }

        if (now >=  info.beginLockedTime.add(info.lockedTime)) return 0;
        return  info.beginLockedTime.add(info.lockedTime).sub(now);
    }
    
    /// @notice     set revoke fee ratio
    function setRevokeFeeRatio(uint ratio)
        public
        onlyOwner 
        isHalted
        returns (bool)
    {
        require(ratio <= RATIO_PRECISE);
        revokeFeeRatio = ratio;
        return true;
    }


    /// @notice         check HTLC transaction exist or not
    /// @param  xHash   hash of HTLC random number
    /// @return exist   return true if exist
    function xHashExist(bytes32 xHash) 
        public 
        view 
        returns(bool exist) 
    {
        return mapXHashHTLCTxs[xHash].status != TxStatus.None;
    }
    
    /// @notice             add HTLC transaction info
    /// @param  direction   HTLC transaction direction
    /// @param  src         HTLC transaction source address
    /// @param  des         HTLC transaction destination address
    /// @param  xHash       hash of HTLC random number
    /// @param  value       HTLC transfer value of token
    /// @param  isFirstHand is HTLC first hand trade?
    /// @param  shadow      shadow address. used for receipt coins on opposite block chain
    function addHTLCTx(TxDirection direction, address src, address des, bytes32 xHash, uint value, bool isFirstHand, address shadow)
        internal
    {
        require(value != 0);
        require(!xHashExist(xHash));
        
        mapXHashHTLCTxs[xHash] = HTLCTx(direction, src, des, value, TxStatus.Locked, isFirstHand ? lockedTime.mul(2) : lockedTime, now);
        if (isFirstHand) mapXHashShadow[xHash] = shadow;
    }
    
    /// @notice             refund coins from HTLC transaction
    /// @param  xHash       hash of HTLC random number
    /// @param  direction   HTLC transaction direction
    /// @return xHash       return hash of HTLC random number
    function refundHTLCTx(bytes32 xHash, TxDirection direction)
        internal
    {
        HTLCTx storage info = mapXHashHTLCTxs[xHash];
        require(info.status == TxStatus.Locked);
        require(info.direction == direction);
        require(info.destination == msg.sender);
        require(now < info.beginLockedTime.add(info.lockedTime));
        
        info.status = TxStatus.Refunded;
    }
    
    /// @notice             revoke HTLC transaction
    /// @param  xHash       hash of HTLC random number
    /// @param  direction   HTLC transaction direction
    /// @param  loose       whether give counterparty revoking right
    function revokeHTLCTx(bytes32 xHash, TxDirection direction, bool loose)
        internal
    {
        HTLCTx storage info = mapXHashHTLCTxs[xHash];
        require(info.status == TxStatus.Locked);
        require(info.direction == direction);
        require(now >= info.beginLockedTime.add(info.lockedTime));
        if (loose) {
            require((info.source == msg.sender) || (info.destination == msg.sender));
        } else {
            require(info.source == msg.sender);
        }

        info.status = TxStatus.Revoked;
    }
    
}
