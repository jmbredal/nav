define([
    'plugins/netmap-extras',
    'netmap/views/info/vlan',
    'libs-amd/text!netmap/templates/widgets/link_info.html',
    'libs/handlebars',
    'libs/jquery',
    'libs/underscore',
    'libs/backbone',
    'libs/backbone-eventbroker'
], function (NetmapExtras, VlanInfoView, netmapTemplate) {

    var LinkInfoView = Backbone.View.extend({
        broker: Backbone.EventBroker,
        interests: {
            "netmap:selectVlan": "setSelectedVlan"
        },
        initialize: function () {
            this.broker.register(this);
            this.template = Handlebars.compile(netmapTemplate);
            Handlebars.registerHelper('toLowerCase', function (value) {
                return (value && typeof value === 'string') ? value.toLowerCase() : '';
            });
            this.link = this.options.link;
            this.vlanView = new VlanInfoView();
        },
        hasLink: function () {
            return !!this.link;
        },
        render: function () {
            var self = this;


            var inOctets, outOctets, inOctetsRaw, outOctetsRaw = "N/A";
            if (self.link !== undefined) {
                /*if (!!self.link.data.get('traffic').inOctets) {
                    inOctets = NetmapExtras.convert_bits_to_si(self.link.data.get('traffic').inOctets.rrd.raw * 8);
                    inOctetsRaw = self.link.data.get('traffic').inOctets.rrd.raw;
                } else {
                    inOctets = inOctetsRaw = 'N/A';
                }
                if (!!self.link.data.get('traffic').outOctets) {
                    outOctets = NetmapExtras.convert_bits_to_si(self.link.data.get('traffic').outOctets.rrd.raw * 8);
                    outOctetsRaw = self.link.data.get('traffic').outOctets.rrd.raw;
                } else {
                    outOctets = outOctetsRaw = 'N/A';
                }*/
                inOctets = inOctetsRaw = outOctets = outOctetsRaw = 'N/A';



                var link =  {};
                _.each(self.link.data, function (data, key) { link[key] = data.toJSON(); });
                var out = this.template({link: link,
                    inOctets: inOctets ,
                    inOctetsRaw: inOctetsRaw,
                    outOctets: outOctets,
                    outOctetsRaw: outOctetsRaw
                });
                console.log(link);

                this.$el.html(out);
                this.$el.append(this.vlanView.render().el);
                this.vlanView.delegateEvents();
            } else {
                this.$el.empty();
            }

            return this;
        },
        setSelectedVlan: function (selected_vlan) {
            this.vlanView.setSelectedVlan(selected_vlan);
            this.render();
        },
        setLink: function (link, selected_vlan) {
            this.link = link;
            this.vlanView.setVlans(link.data.vlans);
            this.vlanView.setSelectedVlan(selected_vlan);
            this.render();
        },
        reset: function () {
            this.link = undefined;
            this.selectedVLANObject = undefined;
            this.vlanView.setVlans(undefined);
            this.render();
        },
        close: function () {
            $(this.el).unbind();
            $(this.el).remove();
        }
    });
    return LinkInfoView;
});





