pragma solidity ^0.4.18;

/**
 * @title Crowdsale
 * @dev Crowdsale is a base contract for managing a token crowdsale.
 * Crowdsales have a start and end timestamps, where investors can make
 * token purchases and the crowdsale will assign them tokens based
 * on a token per ETH rate. Funds collected are forwarded to a wallet
 * as they arrive.
 */
 
 
library SafeMath {
  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

 function div(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b > 0); // Solidity automatically throws when dividing by 0
    uint256 c = a / b;
    assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return c;
  }

  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    assert(c >= a);
    return c;
  }
}

contract Ownable {
  address public owner;


  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);


  /**
   * @dev The Ownable constructor sets the original `owner` of the contract to the sender
   * account.
   */
  function Ownable() public {
    owner = msg.sender;
  }


  /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }


  /**
   * @dev Allows the current owner to transfer control of the contract to a newOwner.
   * @param newOwner The address to transfer ownership to.
   */
  function transferOwnership(address newOwner) onlyOwner public {
    require(newOwner != address(0));
    OwnershipTransferred(owner, newOwner);
    owner = newOwner;
  }

}

interface Token {
    
    function transfer(address _to, uint256 _amount) external returns (bool success);
    function balanceOf(address _owner) external view returns (uint256 balance);
    function decimals() external view returns (uint8);
}

contract SpyceCrowdsale is Ownable{
  using SafeMath for uint256;
 
  // The token being sold
  Token public token;

  // start and end timestamps where investments are allowed (both inclusive)
  uint256 public startTime;
  uint256 public endTime;

  // address where funds are collected
  // address where tokens are deposited and from where we send tokens to buyers
  address public wallet;

  // how many token units a buyer gets per wei
  uint256 public ratePerWei = 10204;

  // amount of raised money in wei
  uint256 public weiRaised;

  //To check whether the contract has been powered up
  bool contractPoweredUp = false;
  
  uint256 TOKENS_SOLD;
  uint256 maxTokensToSale;
 
  
  bool isCrowdsalePaused = false;

  /**
   * event for token purchase logging
   * @param purchaser who paid for the tokens
   * @param beneficiary who got the tokens
   * @param value weis paid for purchase
   * @param amount amount of tokens purchased
   */
  event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);
    
    //modifiers    
     modifier nonZeroAddress(address _to) {
        require(_to != 0x0);
        _;
    }
    
    modifier nonZeroEth() {
        require(msg.value > 0);
        _;
    }

  function SpyceCrowdsale(address _tokenToBeUsed, address _wallet) public nonZeroAddress(_tokenToBeUsed) nonZeroAddress(_wallet) 
  {
    owner = _wallet;
    wallet = _wallet;
    token = Token(_tokenToBeUsed);
  }
  
 
  // fallback function can be used to buy tokens
  function () public payable {
    buyTokens(msg.sender);
  }
   
  // low level token purchase function
  // Minimum purchase can be of 1 ETH
  
  function buyTokens(address beneficiary) public payable nonZeroAddress(beneficiary) nonZeroEth{
    require (contractPoweredUp == true);
    require(isCrowdsalePaused == false);
    require(validPurchase());
    require(TOKENS_SOLD<maxTokensToSale);
    uint256 weiAmount = msg.value;
    
    // calculate token amount to be created
    
    uint256 tokens = weiAmount.mul(ratePerWei);
    require(TOKENS_SOLD+tokens<=maxTokensToSale);
    
    // update state
    weiRaised = weiRaised.add(weiAmount);

    token.transfer(beneficiary, tokens); 
    TokenPurchase(msg.sender, beneficiary, weiAmount, tokens);
    TOKENS_SOLD = TOKENS_SOLD.add(tokens);
    forwardFunds();
  }

  // send ether to the fund collection wallet
  // override to create custom fund forwarding mechanisms
  function forwardFunds() internal {
    wallet.transfer(msg.value);
  }

  // @return true if the transaction can buy tokens
  function validPurchase() internal constant returns (bool) {
    bool withinPeriod = now >= startTime && now <= endTime;
    bool nonZeroPurchase = msg.value != 0;
    return withinPeriod && nonZeroPurchase;
  }

  // @return true if crowdsale event has ended
  function hasEnded() public constant returns (bool) {
    return now > endTime;
  }
  
    /**
     * function to change the end date & time
     * can only be called from owner wallet
     **/
        
    function changeEndTime(uint256 endTimeUnixTimestamp) public onlyOwner returns(bool) {
        endTime = endTimeUnixTimestamp;
    }
    
    /**
     * function to change the start date & time
     * can only be called from owner wallet
     **/
     
    function changeStartTime(uint256 startTimeUnixTimestamp) public onlyOwner returns(bool) {
        startTime = startTimeUnixTimestamp;
    }
    
    /**
     * function to change the price rate 
     * can only be called from owner wallet
     **/
     
    function setPriceRate(uint256 newPrice) public onlyOwner returns (bool) {
        ratePerWei = newPrice;
    }
    
     /**
     * function to pause the crowdsale 
     * can only be called from owner wallet
     **/
     
    function pauseCrowdsale() public onlyOwner returns(bool) {
        isCrowdsalePaused = true;
    }

    /**
     * function to resume the crowdsale if it is paused
     * can only be called from owner wallet
     * if the crowdsale has been stopped, this function would not resume it
     **/ 
    function resumeCrowdsale() public onlyOwner returns (bool) {
        isCrowdsalePaused = false;
    }
    
     /**
      * Remaining tokens for sale
     **/
     function remainingTokensForSale() public constant returns (uint) {
         return maxTokensToSale - TOKENS_SOLD;
     }
     
   /**
   *@dev To power up the contract
   * This will start the sale
   * This will set the end time of the sale
   * It will also check whether the contract has required number of tokens assigned to it or not
   */
   function powerUpContract(uint _startTime, uint _endTime, uint _rate, uint _tokensAvailableInThisRound) public onlyOwner
   {
     require(_endTime > _startTime);
     require(_rate > 0 && _tokensAvailableInThisRound > 0);
     startTime = _startTime;
     endTime = _endTime;
     // Contract should have enough SPYCE credits
     require(token.balanceOf(this) >= _tokensAvailableInThisRound * 10 ** 18);
     
     ratePerWei = _rate;
     contractPoweredUp = true;
     maxTokensToSale = _tokensAvailableInThisRound * 10 ** 18;
     TOKENS_SOLD = 0;
  }
  
  /**
   * This will pull back all the tokens assigned to the contract back in the owner wallet
   * This should be done in case there are unsold tokens and the crowdsale is over
   **/ 
  function pullUnsoldTokensBackToOwnerWallet() public onlyOwner 
  {
      require(token.balanceOf(this)>0);
      uint bal = token.balanceOf(this);
      token.transfer(wallet,bal);
  }
}
