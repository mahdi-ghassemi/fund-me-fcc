// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./PriceConverter.sol";

error NotOwner();

contract FundMe {
    using PriceConverter for uint256;

    /** @dev REFUND_DEAD_TIME_SECONDS is for refundability. After the time is up, it is not possible to refund funders and 
             before that, the SC owner can not withdraw a fund.
    **/
    uint public constant REFUND_DEAD_TIME_SECONDS = 60;

    /** @dev Events definition  */    
    event fundSucceed(address _sender, uint256 _value);
    event withdrawResult(address _sender,uint256 _amount, bool success);

    /** @dev Struct definition 
             Fund structure stores funds history and manages refund dead time.   
    **/
    struct Fund {        
        address payable funderAddress;
        uint256 amount;
        uint256 timestamp; 
        bool withdrawn;       
    }
    

    mapping(address => uint256) public addressToAmountFunded; //balance
    
    Fund[] public funds;
    uint256 public totalFunds;
    

    // Could we make this constant?  /* hint: no! We should make it immutable! */
    address public /* immutable */ i_owner;
    uint256 public constant MINIMUM_USD = 15 * 10 ** 18;

    
    
    constructor() {
        i_owner = msg.sender;        
    }    

     /** @dev Received fund to smart contract        

        @notice The value sent must be greater than MINIMUM_USD
    */
    function fund() public payable {
        require(msg.value.getConversionRate() >= MINIMUM_USD, "You need to spend more ETH!");  
        Fund memory _fund = Fund({            
            funderAddress: payable(msg.sender),
            amount: msg.value,
            timestamp: block.timestamp,
            withdrawn: false           
        });

        funds.push(_fund);
        addressToAmountFunded[msg.sender] += msg.value;
        totalFunds += msg.value;
        emit fundSucceed(msg.sender, msg.value);
    }
    
    function getVersion() public view returns (uint256){
        // ETH/USD price feed address of Sepolia Network.
        AggregatorV3Interface priceFeed = AggregatorV3Interface(0x694AA1769357215DE4FAC081bf1f309aDC325306);
        return priceFeed.version();
    }

     /** @dev Getting current ether price based on USD from Chainlink Oracle            
        @return Ether price based on USD if it's executed successfully
    */
    function getCurrentRate() public view returns (uint256) {
        uint256 value = 1;
        return value.getConversionRate();
    }
    
    modifier onlyOwner {
        // require(msg.sender == owner);
        if (msg.sender != i_owner) revert NotOwner();
        _;
    }

    /** @dev Refund funds from smart contract       

        @notice After the refund dead time expired, it is not possible to refund funders.
    */
    function refund() public {        
        uint256 refundableAmount = 0;
        uint256 length = funds.length;
        for(uint256 fundIndex=0; fundIndex < length;) {
            if(funds[fundIndex].funderAddress == msg.sender) {
                if(funds[fundIndex].timestamp + REFUND_DEAD_TIME_SECONDS >= block.timestamp ){
                    refundableAmount += funds[fundIndex].amount;
                    addressToAmountFunded[msg.sender] -= funds[fundIndex].amount;                    
                }
            }
            unchecked {
                fundIndex++;
            }
        }
        
        (bool callSuccess, ) = payable(msg.sender).call{value: refundableAmount}("");
        totalFunds -= refundableAmount; 
        emit withdrawResult(msg.sender, refundableAmount, callSuccess);
    }
    

    /** @dev Withdraw the free funds from smart contract to owner account.       

        @notice It is not possible for the owner to withdraw that fund before the expiration period.
    */
    function withdraw() public onlyOwner {       
        uint256 removableAmount = 0;
        uint256 length = funds.length;
        for (uint256 fundIndex=0; fundIndex < length;){
            if(!funds[fundIndex].withdrawn) {
                if(funds[fundIndex].timestamp + REFUND_DEAD_TIME_SECONDS < block.timestamp ) {
                    removableAmount += funds[fundIndex].amount;
                    addressToAmountFunded[funds[fundIndex].funderAddress] -= funds[fundIndex].amount;                     
                    funds[fundIndex].withdrawn = true;
                }
            } 
            unchecked {
                fundIndex++;
            }                       
        }   
        
        (bool callSuccess, ) = payable(msg.sender).call{value: removableAmount}("");        
        emit withdrawResult(msg.sender, removableAmount, callSuccess);
        
    }    

    
    fallback() external payable {
        fund();
    }

    receive() external payable {
        fund();
    }

   /** @dev Getting current SC balance            
       @return SC balance
    */
    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    /** @dev Getting total funds amount            
        @return total funds amount

        @notice The refunded funds are not calculate.
    */
    function getTotalFunds() public view returns (uint256) {
        return totalFunds;
    }

    /** @dev Getting the caller balance            
        @return The caller balance        
    */
    function balanceOf() public view returns (uint256) {
        return addressToAmountFunded[msg.sender];
    }

    /** @dev Getting the list of funders            
        @return Funders list        
    */
    function getFundersList() public view returns(Fund[] memory) {
        Fund[] memory _list = funds;
        return _list;   
    }
}
