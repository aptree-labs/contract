/**
The aptree issuer handles the minting and distribution of new trees.
It also maintains control of the tree registry.
The tree registry is an onchain representation of the trees species that are valid in the aptree context.
It also manages the purchases of consumables
**/
module aptree::issuer {

    use std::option;
    use std::signer;
    use std::signer::address_of;
    use std::string;
    use std::vector;
    use aptos_std::debug;
    use aptos_framework::account;
    use aptos_framework::account::{create_signer_with_capability, create_resource_address};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin;
    use aptos_framework::event::emit;
    use aptos_framework::object;
    use aptos_token_objects::aptos_token::AptosToken;
    use aptos_token_objects::collection;
    use aptos_token_objects::token;
    #[test_only]
    use std::signer;
    // #[test_only]
    // use aptos_std::debug;
    #[test_only]
    use aptos_framework::timestamp;

    const SEED: vector<u8> = b"Aptree";
    const SEED_REGISTRY_NAME: vector<u8> = b"Aptree Seed Nursery";
    const SEED_REGISTRY_DESCRIPTION: vector<u8> = b"A collection of seeds waiting to be planted. Each one holds the potential for growth but only action can unlock it. Plant your seed, and begin the journey.";
    const SEED_REGISTY_IMAGE: vector<u8> = b"https://raw.githubusercontent.com/aptree-labs/registry/refs/heads/main/png/arcacia/background.png";

    const PLANTATION_REGISTRY_NAME: vector<u8> = b"Aptree Tree Plantation";
    const PLANTATION_REGISTRY_DESCRIPTION: vector<u8> = b"These seeds have been planted and are now growing. Water them daily, stay consistent, and watch them evolve into something meaningful.";
    const PLANTATION_REGISTRY_IMAGE: vector<u8> = b"https://raw.githubusercontent.com/aptree-labs/registry/refs/heads/main/png/arcacia/background.png";

    const METADATA_BASE_URI: vector<u8> = b"https://drogen-development.up.railway.app/metadata";

    // Errors
    const EOperationNotPermitted: u64 = 403;
    const ERegistryUnInitialized: u64 = 404;
    const ESeedAlreadyPlantedOrDoesNotExist: u64 = 405;

    struct Seed has key, store, drop {
        token_mutator_ref: token::MutatorRef,
        token_burn_ref: token::BurnRef,
        transfer_ref: object::TransferRef,
        specie: string::String,
        metadata_uri: string::String,
        seed_id: string::String
    }

    struct Tree has key, store, drop {
        token_mutator_ref: token::MutatorRef,
        token_burn_ref: token::BurnRef,
        transfer_ref: object::TransferRef,
        specie: string::String,
        id: string::String
    }

    #[event]
    struct AddConsumable has store, drop {
        id: string::String,
        price: u64
    }

    #[event]
    struct ConsumablePurchase has store, drop {
        id: string::String,
        for: address,
    }

    struct Consumable has store, drop {
        id: string::String,
        price: u64
    }

    struct TreeRegistry has key {
        signer_capability: account::SignerCapability,
        seed_collection_mutator_ref: collection::MutatorRef,
        plantation_collection_mutator_ref: collection::MutatorRef,
        issued_seeds: u64,
        planted_trees: u64,
        metadata_base_uri: string::String,
        consumables: vector<Consumable>,
        treasury: address
    }

    #[event]
    struct SeedRegistered has store, drop {
        name: string::String,
        for: address,
        token_address: address,
        seed_id: string::String
    }

    #[event]
    struct TreePlanted has store, drop {
        id: string::String,
        name: string::String,
        by: address,
        token_address: address
    }

    #[event]
    struct PurchaseGrowthFreeze has store, drop {
        address: address
    }

    fun init_module(admin: &signer) {

        let (resource_account_signer, signer_capability) =
            account::create_resource_account(admin, SEED);

        let seed_collection_constructor_ref =
            collection::create_unlimited_collection(
                &resource_account_signer,
                string::utf8(SEED_REGISTRY_DESCRIPTION),
                string::utf8(SEED_REGISTRY_NAME),
                option::none(),
                string::utf8(SEED_REGISTY_IMAGE)
            );

        let seed_registry_mutator_ref =
            collection::generate_mutator_ref(&seed_collection_constructor_ref);

        let plantation_collection_constructor_ref =
            collection::create_unlimited_collection(
                &resource_account_signer,
                string::utf8(PLANTATION_REGISTRY_DESCRIPTION),
                string::utf8(PLANTATION_REGISTRY_NAME),
                option::none(),
                string::utf8(PLANTATION_REGISTRY_IMAGE)
            );

        let plantation_registry_mutator_ref =
            collection::generate_mutator_ref(&plantation_collection_constructor_ref);

        let registry = TreeRegistry {
            issued_seeds: 0,
            planted_trees: 0,
            plantation_collection_mutator_ref: plantation_registry_mutator_ref,
            seed_collection_mutator_ref: seed_registry_mutator_ref,
            signer_capability,
            metadata_base_uri: string::utf8(METADATA_BASE_URI),
            consumables: vector[],
            treasury: signer::address_of(admin)
        };

        move_to<TreeRegistry>(&resource_account_signer, registry);
    }

    entry fun issue_seed(
        admin: &signer,
        for_address: address,
        seed_hash: string::String,
        specie: string::String,
        specie_name: string::String,
        index: string::String
    ) acquires TreeRegistry {
        assert!(address_of(admin) == @aptree, EOperationNotPermitted);

        let resource_address = create_resource_address(&@aptree, SEED);

        let registry = borrow_global_mut<TreeRegistry>(resource_address);

        let resource_signer = create_signer_with_capability(&registry.signer_capability);

        let seed_metadata_uri = registry.metadata_base_uri;
        string::append(&mut seed_metadata_uri, string::utf8(b"/seed/"));
        string::append(&mut seed_metadata_uri, seed_hash);

        let seed_name = string::utf8(b"");

        string::append(&mut seed_name, specie_name);
        string::append(&mut seed_name, string::utf8(b" #"));
        string::append(&mut seed_name, index);

        debug::print(&seed_name);

        registry.issued_seeds = registry.issued_seeds + 1;

        let description = get_description(0, specie);

        let token_constructor_ref =
            token::create_named_token(
                &resource_signer,
                string::utf8(SEED_REGISTRY_NAME),
                description,
                seed_name,
                option::none(),
                seed_metadata_uri
            );

        let token_signer = object::generate_signer(&token_constructor_ref);
        let transfer_ref = object::generate_transfer_ref(&token_constructor_ref);

        let seed = Seed {
            specie,
            token_mutator_ref: token::generate_mutator_ref(&token_constructor_ref),
            token_burn_ref: token::generate_burn_ref(&token_constructor_ref),
            transfer_ref,
            metadata_uri: seed_metadata_uri,
            seed_id: seed_hash
        };

        move_to(&token_signer, seed);

        let seed_obj = object::object_from_constructor_ref<Seed>(&token_constructor_ref);

        object::transfer(&resource_signer, seed_obj, for_address);

        object::disable_ungated_transfer(
            &object::generate_transfer_ref(&token_constructor_ref)
        );

        let token_address =
            token::create_token_address(
                &resource_address, &string::utf8(SEED_REGISTRY_NAME), &seed_name
            );

        emit(
            SeedRegistered {
                name: seed_name,
                for: for_address,
                token_address,
                seed_id: seed_hash
            }
        )

    }

    entry fun plant_seed(user: &signer, seed_name: string::String) acquires Seed, TreeRegistry {
        let user_address = address_of(user);
        let resource_address = account::create_resource_address(&@aptree, SEED);

        let registry = borrow_global_mut<TreeRegistry>(resource_address);

        let resource_signer =
            account::create_signer_with_capability(&registry.signer_capability);

        let seed_address =
            token::create_token_address(
                &resource_address,
                &string::utf8(SEED_REGISTRY_NAME),
                &seed_name
            );

        let seed_obj = object::address_to_object<Seed>(seed_address);

        assert!(exists<Seed>(seed_address), ESeedAlreadyPlantedOrDoesNotExist);
        assert!(object::is_owner(seed_obj, user_address), EOperationNotPermitted);

        let seed = borrow_global_mut<Seed>(seed_address);

        object::enable_ungated_transfer(&seed.transfer_ref);

        let linear_transfer_ref =
            object::generate_linear_transfer_ref(&seed.transfer_ref);
        object::transfer_with_ref(linear_transfer_ref, resource_address);

        let tree_name = seed_name;

        registry.planted_trees = registry.planted_trees + 1;

        let description = get_description(1, seed.specie);

        let plant_metadata_uri = string::utf8(METADATA_BASE_URI);
        string::append(&mut plant_metadata_uri, string::utf8(b"/plant/"));
        string::append(&mut plant_metadata_uri, seed.seed_id);

        let token_constructor_ref =
            token::create_named_token(
                &resource_signer,
                string::utf8(PLANTATION_REGISTRY_NAME),
                description,
                tree_name,
                option::none(),
                plant_metadata_uri
            );

        let token_signer = object::generate_signer(&token_constructor_ref);

        let burn_ref = token::generate_burn_ref(&token_constructor_ref);

        let mutation_ref = token::generate_mutator_ref(&token_constructor_ref);

        let transfer_ref = object::generate_transfer_ref(&token_constructor_ref);

        let token_address =
            token::create_token_address(
                &user_address, &string::utf8(PLANTATION_REGISTRY_NAME), &tree_name
            );

        let planted_tree = Tree {
            specie: seed.specie,
            transfer_ref,
            token_burn_ref: burn_ref,
            token_mutator_ref: mutation_ref,
            id: seed.seed_id
        };

        move_to(&token_signer, planted_tree);

        let tree_obj = object::object_from_constructor_ref<Tree>(&token_constructor_ref);

        object::transfer(&resource_signer, tree_obj, user_address);

        emit(
            TreePlanted {
                id: seed.seed_id,
                name: tree_name,
                token_address,
                by: user_address
            }
        )

    }

    entry fun create_consumable(admin: &signer, id: string::String, price: u64) acquires TreeRegistry {
        assert!(address_of(admin) == @aptree, EOperationNotPermitted);

        let resource_address = account::create_resource_address(&@aptree, SEED);
        let registry = borrow_global_mut<TreeRegistry>(resource_address);

        let consumable = Consumable {
            id,
            price
        };

        vector::push_back(&mut registry.consumables, consumable);

        emit(AddConsumable { id, price });
    }

    entry fun purchase_consumable(user: &signer, id: string::String) acquires TreeRegistry {
        let user_address = address_of(user);
        let resource_address = account::create_resource_address(&@aptree, SEED);
        let registry = borrow_global_mut<TreeRegistry>(resource_address);

        let (exists, index) = vector::find(&registry.consumables, |c| c.id == id);

        assert!(exists, EOperationNotPermitted);

        let consumable = vector::borrow(&registry.consumables, index);

        coin::transfer<AptosCoin>(user, registry.treasury, consumable.price);

        emit(ConsumablePurchase {
            id,
            for: user_address
        })

    }

    entry fun gift_consumable(admin: &signer, receiver: address, id: string::String) acquires TreeRegistry {
        assert!(address_of(admin) == @aptree, EOperationNotPermitted);

        let resource_address = account::create_resource_address(&@aptree, SEED);
        let registry = borrow_global_mut<TreeRegistry>(resource_address);

        let (exists, index) = vector::find(&registry.consumables, |c| c.id == id);

        assert!(exists, EOperationNotPermitted);

        let consumable = vector::borrow(&registry.consumables, index);

        emit(ConsumablePurchase {
            for: receiver,
            id
        })
    }


    inline fun get_description(type: u64, specie: string::String): string::String {
        if (type == 0) {
            if (specie == string::utf8(b"acacia")) {
                string::utf8(
                    b"A hardy acacia seed resilient and waiting to root in tough soil."
                )
            } else if (specie == string::utf8(b"bamboo")) {
                string::utf8(
                    b"A bamboo seed slow to start, but destined for rapid growth."
                )
            } else if (specie == string::utf8(b"baobab")) {
                string::utf8(
                    b"A baobab seed ancient potential wrapped in a thick shell of time."
                )
            } else if (specie == string::utf8(b"birch")) {
                string::utf8(
                    b"A birch seed light, quick to grow, and graceful in the wind."
                )
            } else if (specie == string::utf8(b"cherry-blossom")) {
                string::utf8(
                    b"A delicate cherry blossom seed fragile now, but meant to bloom beautifully."
                )
            } else if (specie == string::utf8(b"eucalyptus")) {
                string::utf8(b"A eucalyptus seed packed with vigor and a healing future.")
            } else if (specie == string::utf8(b"guadalupe-palm")) {
                string::utf8(b"A rare Guadalupe Palm seed patient and enduring.")
            } else if (specie == string::utf8(b"jelly-palm")) {
                string::utf8(b"A jelly palm seed sweet potential lies dormant within.")
            } else if (specie == string::utf8(b"oak")) {
                string::utf8(b"An oak seed slow-growing but destined for strength.")
            } else if (specie == string::utf8(b"spruce")) {
                string::utf8(b"A spruce seed ready to thrive in chill and challenge.")
            } else if (specie == string::utf8(b"willow")) {
                string::utf8(
                    b"A willow seed pliable and poetic, waiting to sway with life."
                )
            } else if (specie == string::utf8(b"yew")) {
                string::utf8(b"A yew seed old magic and longevity sealed inside.")
            } else {
                string::utf8(b"An unknown seed, mysterious and full of hidden promise.")
            }
        } else if (type == 1) {
            if (specie == string::utf8(b"acacia")) {
                string::utf8(b"A growing acacia rooted in resilience, shaped by the sun.")
            } else if (specie == string::utf8(b"bamboo")) {
                string::utf8(b"A bamboo in motion growing swiftly with quiet strength.")
            } else if (specie == string::utf8(b"baobab")) {
                string::utf8(b"A rising baobab sturdy and wise, built to last.")
            } else if (specie == string::utf8(b"birch")) {
                string::utf8(b"A birch tree light-footed and quietly elegant.")
            } else if (specie == string::utf8(b"cherry-blossom")) {
                string::utf8(b"A blooming tree its petals mark your steady progress.")
            } else if (specie == string::utf8(b"eucalyptus")) {
                string::utf8(
                    b"A fragrant eucalyptus steady and strong, breathing healing into Aptree."
                )
            } else if (specie == string::utf8(b"guadalupe-palm")) {
                string::utf8(b"A steadfast palm rare and enduring in its beauty.")
            } else if (specie == string::utf8(b"jelly-palm")) {
                string::utf8(b"A jelly palm bearing sweet signs of growth and care.")
            } else if (specie == string::utf8(b"oak")) {
                string::utf8(
                    b"A mighty oak its trunk thickens with each day of dedication."
                )
            } else if (specie == string::utf8(b"spruce")) {
                string::utf8(b"A spruce tree tall, calm, and unwavering.")
            } else if (specie == string::utf8(b"willow")) {
                string::utf8(b"A willow in sway graceful, responsive, and alive.")
            } else if (specie == string::utf8(b"yew")) {
                string::utf8(b"A mystical yew quietly building ancient presence.")
            } else {
                string::utf8(b"An unidentified tree, growing toward its own story.")
            }
        } else {
            string::utf8(b"A living element of Aptree status unknown.")
        }
    }

    #[test(admin = @aptree)]
    fun test_init_module_success(admin: &signer) acquires aptree::issuer::TreeRegistry {
        // 🛠️ minimal runtime scaffolding (framework signer & ticking clock)
        let aptos_framework = account::create_account_for_test(@0x1);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        // 🚀 initialize issuer
        aptree::issuer::init_module(admin);

        // 🔎 grab the freshly-created registry
        let registry_addr =
            account::create_resource_address(&@aptree, aptree::issuer::SEED);
        let registry = borrow_global<aptree::issuer::TreeRegistry>(registry_addr);

        // ✅ sanity checks
        assert!(registry.issued_seeds == 0, 1);
        assert!(registry.planted_trees == 0, 2);
    }

    #[test(admin = @aptree, user = @0x5)]
    fun test_issue_seed_success(admin: &signer, user: &signer) acquires aptree::issuer::TreeRegistry {
        // 🛠️ framework / clock setup
        let framework = account::create_account_for_test(@0x1);
        timestamp::set_time_has_started_for_testing(&framework);

        // 🚀 bootstrap issuer registry
        aptree::issuer::init_module(admin);

        // 🌱 parameters for the new seed
        let specie = string::utf8(b"acacia");
        let seed_hash = string::utf8(b"hash123");
        let index = string::utf8(b"1");
        let recipient = signer::address_of(user);

        // 🪄  call entry
        aptree::issuer::issue_seed(admin, recipient, seed_hash, specie, index);

        // 🔎 registry updates
        let reg_addr = account::create_resource_address(&@aptree, aptree::issuer::SEED);
        let registry = borrow_global<aptree::issuer::TreeRegistry>(reg_addr);
        assert!(registry.issued_seeds == 1, /*code=*/ 1);

        // 🔎 the seed object must exist and be owned by `recipient`
        // build expected seed name:  "acacia #1"
        let expected_name = string::utf8(b"");
        string::append(&mut expected_name, specie);
        string::append(&mut expected_name, string::utf8(b" #"));
        string::append(&mut expected_name, index);

        let seed_token_addr =
            token::create_token_address(
                &reg_addr,
                &string::utf8(aptree::issuer::SEED_REGISTRY_NAME),
                &expected_name
            );
        debug::print(&expected_name);
        assert!(object::is_object(seed_token_addr), 2);
        assert!(exists<aptree::issuer::Seed>(seed_token_addr), 3);

        let seed_obj = object::address_to_object<aptree::issuer::Seed>(seed_token_addr);
        assert!(object::is_owner(seed_obj, recipient), 4);
    }

    #[test(admin = @aptree, user = @0x5)]
    fun test_plant_seed_success(
        admin: &signer, user: &signer
    ) acquires aptree::issuer::TreeRegistry, aptree::issuer::Seed {
        /* ── 1️⃣  Runtime scaffolding ───────────────────────────────────── */
        let framework = account::create_account_for_test(@0x1);
        timestamp::set_time_has_started_for_testing(&framework);

        /* ── 2️⃣  Boot the issuer module ─────────────────────────────────── */
        aptree::issuer::init_module(admin);

        /* ── 3️⃣  Issue one seed to `user` ───────────────────────────────── */
        let specie = string::utf8(b"acacia");
        let seed_hash = string::utf8(b"hash123");
        let index = string::utf8(b"1");
        let recipient = signer::address_of(user);

        aptree::issuer::issue_seed(admin, recipient, seed_hash, specie, index);

        /* ── 4️⃣  User plants that same seed ─────────────────────────────── */
        // Build the seed's token-name string:  "acacia #1"
        let seed_name = string::utf8(b"");
        string::append(&mut seed_name, specie);
        string::append(&mut seed_name, string::utf8(b" #"));
        string::append(&mut seed_name, index);

        aptree::issuer::plant_seed(user, seed_name);

        /* ── 5️⃣  Assertions ─────────────────────────────────────────────── */
        let reg_addr = account::create_resource_address(&@aptree, aptree::issuer::SEED);
        let registry = borrow_global<aptree::issuer::TreeRegistry>(reg_addr);

        // registry counters
        assert!(registry.issued_seeds == 1, /*code=*/ 1);
        assert!(registry.planted_trees == 1, /*code=*/ 2);

        // tree token address: user-owned, plantation collection
        let tree_token_addr =
            token::create_token_address(
                &reg_addr,
                &string::utf8(aptree::issuer::PLANTATION_REGISTRY_NAME),
                &seed_name
            );

        assert!(object::is_object(tree_token_addr), 3);
        assert!(exists<aptree::issuer::Tree>(tree_token_addr), 4);

        let tree_obj = object::address_to_object<aptree::issuer::Tree>(tree_token_addr);
        assert!(object::is_owner(tree_obj, recipient), 5);

        // original seed must now live at the resource account (no longer at `user`)
        let seed_token_addr =
            token::create_token_address(
                &reg_addr,
                &string::utf8(aptree::issuer::SEED_REGISTRY_NAME),
                &seed_name
            );
        let seed_obj = object::address_to_object<aptree::issuer::Seed>(seed_token_addr);
        assert!(object::is_owner(seed_obj, reg_addr), 6);
    }
}
