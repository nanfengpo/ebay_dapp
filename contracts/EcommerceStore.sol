pragma solidity ^0.4.13;

import "contracts/Escrow.sol";
contract EcommerceStore {
    enum ProductStatus {Open, Sold, Unsold}
    enum ProductCondition {New, Used} // 全新或二手产品

    uint public productIndex; // 最新的产品编号。一开始没有产品，所以编号为0

    mapping (uint => address) productEscrow; // 产品编号与托管合同的地址的对应关系

    /*
       We keep track of who inserted the product through the mapping. The key is the merchant's account address
       and the value is the mapping of productIndex to the Product struct. For example, let's say there are no
       products in our store. A user with account address (0x64fcba11d3dce1e3f781e22ec2b61001d2c652e5) adds
       an iphone to the store to sell. Our stores mapping would now have:

         0x64fcba11d3dce1e3f781e22ec2b61001d2c652e5 => {1 => "struct with iphone details"}

           stores[msg.sender][productIndex] = product;

    */
    mapping(address => mapping(uint => Product)) stores;  // 店铺。每个以太坊地址address都对应一家店铺，每家店铺都拥有许多产品Product
    // 【注意】这里每家店铺的商品也使用字典mapping(uint => Product)的原因是，方便使用id迅速找到相应商品。因为一家店铺里的商品id并不是依次递增的，所以无法使用数组下标来查找。

    /*
      mapping used to keep track of which products are in which merchant's store.
      productIdInStore[productIndex] = msg.sender;
    */
    mapping(uint => address) productIdInStore;  // 产品编号与所在店铺的地址的对应关系

    // 出价
    struct Bid {
        address bidder; // 出价人
        uint productId; // 产品id
        uint value; // 附带金额（不是实际出价金额）
        bool revealed; // 此出价是否已经公告
    }

    struct Product {
        uint id; //产品id
        string name; //产品名字
        string category; //分类
        string imageLink; //图片hash
        string descLink; //图片描述信息的hash
        uint auctionStartTime; //开始竞标的时间
        uint auctionEndTime; // 竞标结束时间
        uint startPrice; // 起拍价格
        address highestBidder; // 赢家的钱包地址
        uint highestBid; // 赢家竞标的价格
        uint secondHighestBid; // 第二高的这个人的地址
        uint totalBids; // 一共有多少人参与竞标
        ProductStatus status; //状态
        ProductCondition condition; // 新、旧

        /*
        To easily lookup which user bid and what they bid, let's add a mapping to the
        product struct mapping (address => mapping (bytes32 => Bid)) bids;. The key is
        the address of the bidder and value is the mapping of the hashed bid string to
        the bid struct.
        */
        mapping (address => mapping (bytes32 => Bid)) bids; // 该产品的出价。address对应每个出价的以太坊账户地址，每个账户可以出多笔价，关键字是实际投标金额和密钥加密后的hash值
    }

    // 构造函数
    function EcommerceStore() public {
        productIndex = 0;
    }

    // https://www.zastrin.com/courses/3/lessons/8-6
    event NewProduct(uint _productId, string _name, string _category, string _imageLink, string _descLink, uint _auctionStartTime, uint _auctionEndTime, uint _startPrice, uint _productCondition);

    /*  添加产品到区块链*/
    function addProductToStore(string _name, string _category, string _imageLink, string _descLink, uint _auctionStartTime,
        uint _auctionEndTime, uint _startPrice, uint _productCondition) public {
        require (_auctionStartTime < _auctionEndTime);
        productIndex += 1;
        Product memory product = Product(productIndex, _name, _category, _imageLink, _descLink, _auctionStartTime, _auctionEndTime,
            _startPrice, 0, 0, 0, 0, ProductStatus.Open, ProductCondition(_productCondition));
        stores[msg.sender][productIndex] = product;
        productIdInStore[productIndex] = msg.sender;
        // 触发事件
        NewProduct(productIndex, _name, _category, _imageLink, _descLink, _auctionStartTime, _auctionEndTime, _startPrice, _productCondition);
    }

    /* 通过产品ID读取产品信息 */
    function getProduct(uint _productId) view public returns (uint, string, string, string, string, uint, uint, uint, ProductStatus, ProductCondition) {
        /*
          https://solidity.readthedocs.io/en/latest/frequently-asked-questions.html#what-is-the-memory-keyword-what-does-it-do
           memory keyword is to tell the EVM that this object is only used as a temporary variable. It will be cleared from memory
           as soon as this function completes execution
        */
        Product memory product = stores[productIdInStore[_productId]][_productId];
        return (product.id, product.name, product.category, product.imageLink, product.descLink, product.auctionStartTime,
        product.auctionEndTime, product.startPrice, product.status, product.condition);
    }

    // 出价。其中
    // 1) _bid是􏰜􏸌􏶺􏶘􏴍􏷏􏲍􏱁􏱂􏶦􏸓􏱜􏶦􏰜􏸌􏶺􏶘􏴍􏷏􏲍􏱁􏱂􏶦􏸓􏱜􏶦实际投标金额和密钥加密后的hash值
    // 2) msg.value是附带的金额
    function bid(uint _productId, bytes32 _bid) payable public returns (bool) {
        Product storage product = stores[productIdInStore[_productId]][_productId]; // 根据产品id找到该产品在stores中的对象
        require (now >= product.auctionStartTime); // 注意now是关键字，表示当前时间
        require (now <= product.auctionEndTime);
        require (msg.value > product.startPrice);
        require (product.bids[msg.sender][_bid].bidder == 0);
        product.bids[msg.sender][_bid] = Bid(msg.sender, _productId, msg.value, false); // 新建一个bid对象。键是_bid，值是新建的Bid对象
        product.totalBids += 1;
        return true;
    }

    function stringToUint(string s) pure private returns (uint) {
        bytes memory b = bytes(s);
        uint result = 0;
        for (uint i = 0; i < b.length; i++) {
            if (b[i] >= 48 && b[i] <= 57) {
                result = result * 10 + (uint(b[i]) - 48);
            }
        }
        return result;
    }

    // 公告。
    function revealBid(uint _productId, string _amount, string _secret) public {
        Product storage product = stores[productIdInStore[_productId]][_productId];
        require (now > product.auctionEndTime);
        bytes32 sealedBid = sha3(_amount, _secret);

        Bid memory bidInfo = product.bids[msg.sender][sealedBid];
        require (bidInfo.bidder > 0);
        require (bidInfo.revealed == false);

        uint refund; // 退款

        uint amount = stringToUint(_amount);

        if(bidInfo.value < amount) {
            // They didn't send enough amount, they lost
            refund = bidInfo.value;
        } else {
            // If first to reveal set as highest bidder
            if (address(product.highestBidder) == 0) {
                product.highestBidder = msg.sender;
                product.highestBid = amount;
                product.secondHighestBid = product.startPrice;
                refund = bidInfo.value - amount;
            } else {
                if (amount > product.highestBid) {
                    product.secondHighestBid = product.highestBid;
                    product.highestBidder.transfer(product.highestBid);
                    product.highestBidder = msg.sender;
                    product.highestBid = amount;
                    refund = bidInfo.value - amount;
                } else if (amount > product.secondHighestBid) {
                    product.secondHighestBid = amount;
                    refund = amount;
                } else {
                    refund = amount;
                }
            }
            if (refund > 0) {
                msg.sender.transfer(refund);
                product.bids[msg.sender][sealedBid].revealed = true;
            }
        }
    }

    function highestBidderInfo(uint _productId) view public returns (address, uint, uint) {
        Product memory product = stores[productIdInStore[_productId]][_productId];
        return (product.highestBidder, product.highestBid, product.secondHighestBid);
    }

    function totalBids(uint _productId) view public returns (uint) {
        Product memory product = stores[productIdInStore[_productId]][_productId];
        return product.totalBids;
    }

    // 结束拍卖，并签订托管合同。本交易的发起者作为仲裁者
    function finalizeAuction(uint _productId) public {
        Product memory product = stores[productIdInStore[_productId]][_productId];
        // 48 hours to reveal the bid
        require(now > product.auctionEndTime);
        require(product.status == ProductStatus.Open);
        require(product.highestBidder != msg.sender); // 不能是买家
        require(productIdInStore[_productId] != msg.sender); // 也不能是卖家

        if (product.totalBids == 0) {
            product.status = ProductStatus.Unsold;
        } else {
            // Whoever finalizes the auction is the arbiter
            Escrow escrow = (new Escrow).value(product.secondHighestBid)(_productId, product.highestBidder, productIdInStore[_productId], msg.sender);
            productEscrow[_productId] = address(escrow);
            product.status = ProductStatus.Sold;
            // The bidder only pays the amount equivalent to second highest bidder
            // Refund the difference
            uint refund = product.highestBid - product.secondHighestBid;
            product.highestBidder.transfer(refund);

        }
    }

    // 查询某个产品的托管合同地址
    function escrowAddressForProduct(uint _productId) view public returns (address) {
        return productEscrow[_productId];
    }

    // 查询某个产品的托管合同详情
    function escrowInfo(uint _productId) view public returns (address, address, address, bool, uint, uint) {
        return Escrow(productEscrow[_productId]).escrowInfo();
    }

    // 释放钱款给卖家
    function releaseAmountToSeller(uint _productId) public {
        Escrow(productEscrow[_productId]).releaseAmountToSeller(msg.sender);
    }

    // 退款
    function refundAmountToBuyer(uint _productId) public {
        Escrow(productEscrow[_productId]).refundAmountToBuyer(msg.sender);
    }



}
