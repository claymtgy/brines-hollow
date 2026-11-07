class_name TradeRules
extends RefCounted
## Server-side trade validation against the merchant's authoritative stock and contracts.
## Player inventories are client-simulated (trusted co-op, see net/session.gd), so the
## client escrows its side first (pays brass / hands over goods) and the server decides
## whether the merchant side happens. A rejected trade is refunded by the client.


## Buying from the merchant. Returns the brass cost, or -1 if the merchant can't sell it.
static func server_buy(m: MerchantBoat, item: StringName, count: int) -> int:
	if count <= 0 or count > 99 or not m.selling_prices.has(item) or not m.stock.has_item(item, count):
		return -1
	m.stock.remove_item(item, count)
	return int(m.selling_prices[item]) * count


## Selling to the merchant. Returns the brass payout, or -1 if they don't buy it.
static func server_sell(m: MerchantBoat, item: StringName, count: int) -> int:
	if count <= 0 or count > 999 or not m.buying_prices.has(item):
		return -1
	return int(m.buying_prices[item]) * count


## Export manifest. Returns {brass, scrip, reqs} or {} if unknown / already fulfilled.
static func server_fulfill(m: MerchantBoat, contract_id: StringName) -> Dictionary:
	for c: TradeContract in m.active_contracts:
		if c.id == contract_id and not c.is_fulfilled:
			c.is_fulfilled = true
			return {"brass": c.payout_brass, "scrip": c.payout_scrip, "reqs": c.required_items.duplicate()}
	return {}


static func price_to_buy(m: MerchantBoat, item: StringName, count: int) -> int:
	return int(m.selling_prices.get(item, 0)) * count


static func serialize_merchant(m: MerchantBoat) -> Dictionary:
	var contracts := []
	for c: TradeContract in m.active_contracts:
		contracts.append(c.serialize())
	return {"name": m.merchant_name, "type": int(m.type), "stock": m.stock.serialize(),
		"buy": m.buying_prices.duplicate(), "sell": m.selling_prices.duplicate(), "contracts": contracts}


static func deserialize_merchant(d: Dictionary) -> MerchantBoat:
	var m := MerchantBoat.new(String(d.get("name", "Merchant")), int(d.get("type", 0)) as MerchantBoat.MerchantType)
	m.stock.deserialize(d.get("stock", {}))
	m.buying_prices = d.get("buy", m.buying_prices)
	m.selling_prices = d.get("sell", m.selling_prices)
	m.active_contracts.clear()
	for cd: Dictionary in d.get("contracts", []):
		m.active_contracts.append(TradeContract.deserialize(cd))
	return m
