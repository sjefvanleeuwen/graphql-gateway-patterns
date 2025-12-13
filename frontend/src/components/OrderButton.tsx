import { useMutation, gql } from '@apollo/client';
import toast from 'react-hot-toast';

const PLACE_ORDER = gql`
  mutation PlaceOrder($productId: String!, $quantity: Int!) {
    placeOrder(productId: $productId, quantity: $quantity) {
      id
      status
    }
  }
`;

export default function OrderButton({ productId }: { productId: string }) {
  const [placeOrder, { loading }] = useMutation(PLACE_ORDER, {
    onCompleted: (data) => {
      toast.success(`Order placed! ID: ${data.placeOrder.id}`);
    },
    onError: (error) => {
      toast.error(`Failed to place order: ${error.message}`);
    }
  });

  return (
    <button 
      onClick={() => placeOrder({ variables: { productId, quantity: 1 } })}
      disabled={loading}
    >
      {loading ? 'Ordering...' : 'Buy Now'}
    </button>
  );
}
