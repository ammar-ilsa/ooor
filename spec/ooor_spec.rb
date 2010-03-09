require "lib/ooor.rb"

describe Ooor do
  before(:all) do
    @url = 'http://localhost:8069/xmlrpc'
    @db_password = 'admin'
    @username = 'admin'
    @password = 'admin'
    @database = 'ooor_test'
    @ooor = Ooor.new(:url => @url, :username => @username, :admin => @password)
  end

  it "should keep quiet if no database is mentioned" do
    @ooor.loaded_models.should be_empty
  end

  it "should be able to list databases" do
    @ooor.list.should be_kind_of(Array) 
  end

  it "should be able to create a new database with demo data" do
    unless @ooor.list.index(@database)
      @ooor.create(@db_password, @database)
    end
    @ooor.list.index(@database).should_not be_nil
  end

  
  describe "Configure existing database" do
    before(:all) do
      @ooor = Ooor.new(:url => @url, :username => @username, :admin => @password, :database => @database)
    end

    it "should be able to load a profile" do
      manufacturing_module_id = IrModuleModule.search([['name','=', 'profile_manufacturing']])[0]
      unless IrModuleModule.find(manufacturing_module_id).state = "installed"
        w = @ooor.old_wizard_step('base_setup.base_setup')
        w.company(:profile => manufacturing_module_id)
        w.update(:name => 'Akretion.com')
        w.finish(:state_id => false)
        @ooor.load_models
        @ooor.loaded_models.should_not be_empty
      end
    end

    it "should be able to configure the database" do
      chart_module_id = IrModuleModule.search([['category_id', '=', 'Account Charts'], ['name','=', 'l10n_fr']])[0]
      unless IrModuleModule.find(chart_module_id).state == "installed"
        w2 = AccountConfigWizard.create(:charts => chart_module_id)
        w2.action_create
        w3 = WizardMultiChartsAccounts.create
        w3.action_create
      end
    end
  end


  describe "Do operations on configured database" do
    before(:all) do
      @ooor = Ooor.new(:url => @url, :username => @username, :admin => @password, :database => @database)
    end

    describe "Finders operations" do

      it "should be able to find data by id" do
        p = ProductProduct.find(1)
        p.should_not be_nil
        l = ProductProduct.find([1,2])
        l.size.should == 2
        a = AccountInvoice.find(1)
        a.should_not be_nil
      end

      it "should be able to specify the fields to read" do
        p = ProductProduct.find(1, :fields=>["state", "id"])
        p.should_not be_nil
      end

      it "should be able to find using ir.model.data absolute ids" do
        p = ProductProduct.find('product_product_pc1')
        p.should_not be_nil
        p = ProductProduct.find('product.product_product_pc1')#module scoping is optionnal
        p.should_not be_nil
      end

      it "should be able to use OpenERP domains" do
        partners = ResPartner.find(:all, :domain=>[['supplier', '=', 1],['active','=',1]], :fields=>["id", "name"])
        partners.should_not be_empty
        products = ProductProduct.find(:all, :domain=>[['categ_id','=',1],'|',['name', '=', 'PC1'],['name','=','PC2']])
        products.should be_kind_of(Array)
      end

      it "should mimic ActiveResource scoping" do
        partners = ResPartner.find(:all, :params => {:supplier => true})
        partners.should_not be_empty
      end

      it "should support OpenERP context in finders" do
        p = ProductProduct.find(1, :context => {:my_key => 'value'})
        p.should_not be_nil
      end

      it "should support OpenERP search method" do
        partners = ResPartner.search([['name', 'ilike', 'a']], 0, 2)
        partners.should_not be_empty
      end

      it "should cast dates properly from OpenERP to Ruby" do
        o = SaleOrder.find(1)
        o.date_order.should be_kind_of(Date)
        m = StockMove.find(1)
        m.date.should be_kind_of(Time)
      end

    end

    describe "Relations reading" do
      it "should read many2one relations" do
        o = SaleOrder.find(1)
        o.partner_id.should be_kind_of(ResPartner)
        p = ProductProduct.find(1) #inherited via product template
        p.categ_id.should be_kind_of(ProductCategory)
      end

      it "should read one2many relations" do
        o = SaleOrder.find(1)
        o.order_line.each do |line|
          line.should be_kind_of(SaleOrderLine)
        end
      end

      it "should read many2many relations" do
        SaleOrder.find(1).order_line[1].invoice_ids.should be_kind_of(Array)
      end

      it "should read polymorphic references" do
        IrUiMenu.find(:first, :domain => [['name', '=', 'Partners'], ['parent_id', '!=', false]]).action.should be_kind_of(IrActionsAct_window)
      end
    end

    describe "Basic creations" do
      it "should be able to create a product" do
        p = ProductProduct.create(:name => "testProduct1", :categ_id => 1)
        ProductProduct.find(p.id).categ_id.id.should == 1
        p = ProductProduct.new(:name => "testProduct1")
        p.categ_id = 1
        p.save
        p.categ_id.id.should == 1
      end

      it "should be able to create an order" do
        o = SaleOrder.create(:partner_id => ResPartner.search([['name', 'ilike', 'Agrolait']])[0], 
          :partner_order_id => 1, :partner_invoice_id => 1, :partner_shipping_id => 1, :pricelist_id => 1)
        o.id.should be_kind_of(Integer)
      end

      it "should be able to to create an invoice" do
        i = AccountInvoice.new(:origin => 'ooor_test')
        partner_id = ResPartner.search([['name', 'ilike', 'Agrolait']])[0]
        i.on_change('onchange_partner_id', :partner_id, partner_id, 'out_invoice', partner_id, false, false)
        i.save
        i.id.should be_kind_of(Integer)
      end

      it "should be able to call on_change" do
        o = SaleOrder.new
        partner_id = ResPartner.search([['name', 'ilike', 'Agrolait']])[0]
        o.on_change('onchange_partner_id', :partner_id, partner_id, partner_id)
        o.save
        line = SaleOrderLine.new(:order_id => o.id)
        product_id = 1
        pricelist_id = 1
        product_uom_qty = 1
        line.on_change('product_id_change', :product_id, product_id, pricelist_id, product_id, product_uom_qty, false, 1, false, false, o.partner_id.id, 'en_US', true, false, false, false)
        line.save
        SaleOrder.find(o.id).order_line.size.should == 1
      end

      it "should use default fields on creation" do
        p = ProductProduct.new
        p.sale_delay.should be_kind_of(Integer)
      end
    end

    describe "Basic updates" do
      it "should cast properly from Ruby to OpenERP" do
        #TODO
      end
    end

    describe "Relations assignations" do
      it "should be able to do product.taxes_id = [1,2]" do
        p = ProductProduct.find(1)
        p.taxes_id = [1, 2]
        p.save
        p.taxes_id[0].id.should == 1
        p.taxes_id[1].id.should == 2
      end

      it "should be able to create one2many relations on the fly" do
        #TODO
      end

      it "should be able to assign a polymorphic relation" do
        #TODO implement!
      end
    end

    describe "Old wizard management" do
      it "should be possible to pay an invoice" do
        #TODO
      end
    end

    describe "New style wizards" do
      #TODO
    end

    describe "Delete resources" do
      it "should be able to call unlink" do
        ids = ProductProduct.search([['name', 'ilike', 'testProduct']])
        ProductProduct.unlink(ids)
      end

      it "should be able to destroy loaded business objects" do
        orders = SaleOrder.find(:all, :domain => [['origin', 'ilike', 'ooor_test']])
        orders.each {|order| order.destroy}

        invoices = AccountInvoice.find(:all, :domain => [['origin', 'ilike', 'ooor_test']])
        invoices.each {|inv| inv.destroy}
      end
    end

  end


  describe "Offer Web Client core features" do
    before(:all) do
      @ooor = Ooor.new(:url => @url, :username => @username, :admin => @password, :database => @database)
    end

    it "should find the default user action" do
      @ooor.get_init_menu(1)
    end

    it "should be able to find the sub-menus of a menu" do
      menu = IrUiMenu.find(:first, :domain => [['name', '=', 'Partners'], ['parent_id', '!=', false]])
      menu.child_id.each do |sub_menu|
        sub_menu.should be_kind_of(IrUiMenu)
      end
    end

    it "should retrieve the action of a menu" do
      IrUiMenu.find(:first, :domain => [['name', '=', 'Partners'], ['parent_id', '!=', false]]).action.should be_kind_of(IrActionsAct_window)
    end

    it "should be able to open a list view of a menu action" do
      @ooor.menu_class.find(:first, :domain => [['name', '=', 'Partners'], ['parent_id', '!=', false]]).action.open('tree')
    end

    it  "should be able to open a form view of a menu action" do
      @ooor.menu_class.find(:first, :domain => [['name', '=', 'Partners'], ['parent_id', '!=', false]]).action.open('form', [1])
    end
  end


  describe "UML features" do
    it "should be able to draw the UML of any class" do
      #TODO
    end

    it "should be able to draw the UML of sevaral classes" do
      #TODO
    end
  end


  describe "Multi-instance" do
    it "should be able to read in one instance and write in an other" do
      #TODO
    end
  end

end