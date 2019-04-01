pragma solidity ^0.4.11;

import "./HTLCBase.sol";
import "./StoremanGroupAdminInterface.sol";
import "./WTokenManagerInterface.sol";



contract HTLCWETH is HTLCBase {

    /**
    *
    * VARIABLES
    *
    */

    /// @notice weth manager address
    address public wethManager;

    /// @notice storeman group admin address
    address public storemanGroupAdmin;

    /// @notice transaction fee
    mapping(bytes32 => uint) public mapXHashFee;

    /// @notice token index of WETH
    uint public constant ETH_INDEX = 0;

    /**
    *
    * EVENTS
    *
    **/

    /// @notice            event of exchange WETH with ETH request
    /// @param storeman    address of storeman
    /// @param wanAddr     address of wanchain, used to receive WETH
    /// @param xHash       hash of HTLC random number
    /// @param value       HTLC value
    event ETH2WETHLock(address indexed storeman, address indexed wanAddr, bytes32 indexed xHash, uint value);
    /// @notice            event of refund WETH from exchange WETH with ETH HTLC transaction
    /// @param wanAddr     address of user on wanchain, used to receive WETH
    /// @param storeman    address of storeman, the WETH minter
    /// @param xHash       hash of HTLC random number
    /// @param x           HTLC random number
    event ETH2WETHRefund(address indexed wanAddr, address indexed storeman, bytes32 indexed xHash, bytes32 x);
    /// @notice            event of revoke exchange WETH with ETH HTLC transaction
    /// @param storeman    address of storeman
    /// @param xHash       hash of HTLC random number
    event ETH2WETHRevoke(address indexed storeman, bytes32 indexed xHash);
    /// @notice            event of exchange ETH with WETH request
    /// @param wanAddr     address of user, where the WETH come from
    /// @param storeman    address of storeman, where the ETH come from
    /// @param xHash       hash of HTLC random number
    /// @param value       exchange value
    /// @param ethAddr     address of ethereum, used to receive ETH
    /// @param fee         exchange fee
    event WETH2ETHLock(address indexed wanAddr, address indexed storeman, bytes32 indexed xHash, uint value, address ethAddr, uint fee);
    /// @notice            event of refund WETH from exchange ETH with WETH HTLC transaction
    /// @param storeman    address of storeman, used to receive WETH
    /// @param wanAddr     address of user, where the WETH come from
    /// @param xHash       hash of HTLC random number
    /// @param x           HTLC random number
    event WETH2ETHRefund(address indexed storeman, address indexed wanAddr, bytes32 indexed xHash, bytes32 x);
    /// @notice            event of revoke exchange ETH with WETH HTLC transaction
    /// @param wanAddr     address of user
    /// @param xHash       hash of HTLC random number
    event WETH2ETHRevoke(address indexed wanAddr, bytes32 indexed xHash);

    /**
    *
    * MODIFIERS
    *
    */

    /// @dev Check WETHManager address must be initialized before call its method
    modifier initialized() {
        require(wethManager != address(0));
        require(storemanGroupAdmin != address(0));
        _;
    }

    /**
    *
    * MANIPULATIONS
    *
    */

    /// @notice         set weth manager SC address(only owner have the right)
    /// @param  addr    weth manager SC address
    function setWETHManager(address addr)
        public 
        onlyOwner 
        isHalted
        returns (bool)
    {
        require(addr != address(0));
        wethManager = addr;
        return true;
    }

    /// @notice         set storeman group admin SC address(only owner have the right)
    /// @param  addr    storeman group admin SC address
    function setStoremanGroupAdmin(address addr)
        public
        onlyOwner
        isHalted
        returns (bool)
    {
        require(addr != address(0));
        storemanGroupAdmin = addr;
        return true;
    }

    /// @notice         request exchange WETH with ETH(to prevent collision, x must be a 256bit random bigint) 
    /// @param xHash    hash of HTLC random number
    /// @param wanAddr  address of user, used to receive WETH
    /// @param value    exchange value
    function eth2wethLock(bytes32 xHash, address wanAddr, uint value) 
        public 
        initialized 
        notHalted
        returns(bool) 
    {
        addHTLCTx(TxDirection.Coin2Wtoken, msg.sender, wanAddr, xHash, value, false, address(0x00));
        if (!WTokenManagerInterface(wethManager).lockQuota(msg.sender, wanAddr, value)) {
            revert();
        }

        emit ETH2WETHLock(msg.sender, wanAddr, xHash, value);
        return true;
    }

    /// @notice  refund WETH from the HTLC transaction of exchange WETH with ETH(must be called before HTLC timeout)
    /// @param x HTLC random number
    function eth2wethRefund(bytes32 x) 
        public 
        initialized 
        notHalted
        returns(bool) 
    {
        bytes32 xHash = keccak256(x);
        refundHTLCTx(xHash, TxDirection.Coin2Wtoken);
        HTLCTx storage info = mapXHashHTLCTxs[xHash];
        if (!WTokenManagerInterface(wethManager).mintToken(info.source, info.destination, info.value)) {
            revert();
        }

        emit ETH2WETHRefund(info.destination, info.source, xHash, x);
        return true;
    }

    /// @notice revoke HTLC transaction of exchange WETH with ETH(must be called after HTLC timeout)
    /// @param  xHash  hash of HTLC random number
    function eth2wethRevoke(bytes32 xHash) 
        public 
        initialized 
        notHalted
        returns(bool) 
    {
        revokeHTLCTx(xHash, TxDirection.Coin2Wtoken, false);
        HTLCTx storage info = mapXHashHTLCTxs[xHash];
        if (!WTokenManagerInterface(wethManager).unlockQuota(info.source, info.value)) {
            revert();
        }

        emit ETH2WETHRevoke(info.source, xHash);
        return true;
    }

    /// @notice         request exchange ETH with WETH(to prevent collision, x must be a 256bit random bigint)
    /// @param xHash    hash of HTLC random number
    /// @param storeman address of storeman, where the ETH come from
    /// @param ethAddr  address of ethereum, used to receive ETH
    /// @param value    exchange value
    function weth2ethLock(bytes32 xHash, address storeman, address ethAddr, uint value) 
        public 
        initialized
        notHalted
        payable
        returns(bool) 
    {
        require(!isContract(msg.sender));
        
        // check withdraw fee
        uint fee = getWeth2EthFee(storeman, value);
        require(msg.value >= fee);

        addHTLCTx(TxDirection.Wtoken2Coin, msg.sender, storeman, xHash, value, true, ethAddr);
        if (!WTokenManagerInterface(wethManager).lockToken(storeman, msg.sender, value)) {
            revert();
        }
        
        mapXHashFee[xHash] = fee;
        
        // restore the extra cost
        uint left = msg.value.sub(fee);
        if (left != 0) {
            msg.sender.transfer(left);
        }

        emit WETH2ETHLock(msg.sender, storeman, xHash, value, ethAddr, fee);
        return true;
    }

    /// @notice  refund WETH from the HTLC transaction of exchange ETH with WETH(must be called before HTLC timeout)
    /// @param x HTLC random number
    function weth2ethRefund(bytes32 x) 
        public 
        initialized 
        notHalted
        returns(bool) 
    {
        bytes32 xHash = keccak256(x);
        refundHTLCTx(xHash, TxDirection.Wtoken2Coin);
        HTLCTx storage info = mapXHashHTLCTxs[xHash];
        if (!WTokenManagerInterface(wethManager).burnToken(info.destination, info.value)) {
            revert();
        }

        info.destination.transfer(mapXHashFee[xHash]);
        emit WETH2ETHRefund(info.destination, info.source, xHash, x);
        return true;
    }

    /// @notice        revoke HTLC transaction of exchange ETH with WETH(must be called after HTLC timeout)
    /// @notice        the revoking fee will be sent to storeman
    /// @param  xHash  hash of HTLC random number
    function weth2ethRevoke(bytes32 xHash) 
        public 
        initialized 
        notHalted
        returns(bool) 
    {
        revokeHTLCTx(xHash, TxDirection.Wtoken2Coin, true);
        HTLCTx storage info = mapXHashHTLCTxs[xHash];
        if (!WTokenManagerInterface(wethManager).unlockToken(info.destination, info.source, info.value)) {
            revert();
        }

        uint revokeFee = mapXHashFee[xHash].mul(revokeFeeRatio).div(RATIO_PRECISE);
        uint left = mapXHashFee[xHash].sub(revokeFee);

        if (revokeFee > 0) {
            info.destination.transfer(revokeFee);
        }
        
        if (left > 0) {
            info.source.transfer(left);
        }
        
        emit WETH2ETHRevoke(info.source, xHash);
        return true;
    }
    
    /// @notice          getting weth 2 eth fee
    /// @param  storeman address of storeman
    /// @param  value    HTLC tx value
    /// @return          needful fee
    function getWeth2EthFee(address storeman, uint value)
        public
        view
        returns(uint)
    {
        StoremanGroupAdminInterface smga = StoremanGroupAdminInterface(storemanGroupAdmin);
        uint defaultPrecise = smga.DEFAULT_PRECISE();
        var (coin2WanRatio,,,,,,,,,,,) = smga.mapCoinInfo(ETH_INDEX);
        var (,,,txFeeratio,,,) = smga.mapCoinSmgInfo(ETH_INDEX, storeman);
        return value.mul(coin2WanRatio).mul(txFeeratio).div(defaultPrecise).div(defaultPrecise);
    }

    /// @notice      internal function to determine if an address is a contract
    /// @param  addr the address being queried
    /// @return      true if `addr` is a contract
    function isContract(address addr) 
        internal 
        view 
        returns(bool) 
    {
        uint size;
        if (addr == 0) return false;
        assembly {
            size := extcodesize(addr)
        }
        
        return size > 0;
    }

}